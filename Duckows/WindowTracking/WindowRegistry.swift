import AppKit
import Combine

/// The authoritative list of open windows, and the single thing the bars watch.
///
/// Events arrive far faster than a taskbar needs to redraw — a terminal retitles
/// on every keystroke — so everything funnels through a debounce, and `items`
/// is only reassigned when it genuinely differs.
@MainActor
final class WindowRegistry: ObservableObject {
    static let shared = WindowRegistry()

    @Published private(set) var items: [TaskbarItem] = []
    @Published private(set) var lastScanDuration: TimeInterval = 0
    /// Displays currently showing a true full-screen window.
    ///
    /// A full-screen window owns its whole display and cannot be shortened, so
    /// the only way to keep the bar off it is for the bar to step aside.
    @Published private(set) var fullscreenScreenUUIDs: Set<String> = []

    private let scanner = WindowScanner()
    private var records: [WindowRecord] = []
    private var frontmostPID: pid_t?
    private var focusedWindowID: CGWindowID?

    private var rescanTask: Task<Void, Never>?
    private var isScanning = false
    private var needsAnotherPass = false

    /// Where each button sits, assigned the first time it is seen and never
    /// revised.
    ///
    /// Records come back in `NSWorkspace.runningApplications` order, which is
    /// not stable — it shifts as apps are activated. Rendering in that order
    /// made buttons wander: minimizing a window moved it to the end of the bar
    /// rather than leaving it where it was. A Windows taskbar keeps a button in
    /// the slot it was born in, and so does this.
    private var slots: [String: Int] = [:]
    private var nextSlot = 0

    /// Structural changes should feel immediate; title changes must not, or a
    /// terminal would rebuild the bar on every keystroke.
    private static let structuralDebounce = Duration.milliseconds(60)
    private static let titleDebounce = Duration.milliseconds(250)

    private init() {}

    func start() {
        AXBridge.configureSystemTimeout()
        setNeedsRescan(.structural)
    }

    enum Reason {
        case structural
        case title

        var debounce: Duration {
            switch self {
            case .structural: return WindowRegistry.structuralDebounce
            case .title: return WindowRegistry.titleDebounce
            }
        }
    }

    func setNeedsRescan(_ reason: Reason) {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: reason.debounce)
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    /// Records which app owns the keyboard, so the active button can be
    /// highlighted without a full rescan.
    func setFrontmost(pid: pid_t?) {
        guard frontmostPID != pid else { return }
        frontmostPID = pid
        rebuildItems()
    }

    // MARK: - Scanning

    private func rescan() {
        // Without Accessibility there are no window titles to be had, so fall
        // back to a per-app bar rather than showing nothing.
        guard PermissionMonitor.shared.isAccessibilityTrusted else {
            records = []
            rebuildFromRunningApps()
            return
        }

        guard !isScanning else {
            needsAnotherPass = true
            return
        }
        isScanning = true

        let started = Date()
        let context = ScanContext.current()
        scanner.scan(context: context, previous: records) { [weak self] result in
            guard let self else { return }
            let records = result.records
            let elapsed = Date().timeIntervalSince(started)
            self.lastScanDuration = elapsed
            // A sweep is synchronous IPC into every running app, so it is the
            // one thing here that can quietly get slow as the machine fills up.
            if elapsed > 0.25 {
                NSLog("Duckows: slow window sweep – %.0f ms for %d windows",
                      elapsed * 1000, records.count)
            }
            self.apply(records)
            self.isScanning = false
            if self.needsAnotherPass {
                self.needsAnotherPass = false
                self.setNeedsRescan(.structural)
            }
        }
    }

    private func apply(_ fresh: [WindowRecord]) {
        // A minimized window reports a stale position, so it would otherwise
        // appear to jump to whichever display the origin happens to land on.
        var merged = fresh
        for index in merged.indices where merged[index].isMinimized {
            if let previous = records.first(where: { $0.id == merged[index].id }),
               let known = previous.screenUUID {
                merged[index].screenUUID = known
            }
        }
        records = merged

        let fullscreen = Set(merged.filter(\.isFullscreen).compactMap(\.screenUUID))
        if fullscreen != fullscreenScreenUUIDs {
            fullscreenScreenUUIDs = fullscreen
        }

        rebuildItems()
        MaximizeGuard.shared.apply(to: merged)
    }

    private func rebuildItems() {
        let grouping = SettingsStore.shared.settings.taskbar.grouping
        let next: [TaskbarItem]

        switch grouping {
        case .perWindow:
            next = records.map { record in
                TaskbarItem(
                    id: TaskbarItem.windowID(record.id),
                    title: record.title,
                    pid: record.pid,
                    bundleIdentifier: record.bundleIdentifier,
                    windowIDs: [record.id],
                    isActive: record.pid == frontmostPID && record.isVisible,
                    isMinimized: record.isMinimized,
                    isHidden: !record.isVisible,
                    screenUUID: record.screenUUID
                )
            }
        case .byApp:
            // Keyed by bundle, not by process. Firefox runs a separate process
            // per profile and Chrome does much the same, so grouping by pid
            // showed one button per profile while claiming to group by app.
            var order: [String] = []
            var grouped: [String: [WindowRecord]] = [:]
            for record in records {
                let key = record.bundleIdentifier ?? "pid:\(record.pid)"
                if grouped[key] == nil { order.append(key) }
                grouped[key, default: []].append(record)
            }
            next = order.compactMap { key in
                guard let group = grouped[key], let first = group.first else { return nil }
                return TaskbarItem(
                    id: "a:\(key)",
                    title: first.appName.isEmpty ? first.title : first.appName,
                    pid: first.pid,
                    bundleIdentifier: first.bundleIdentifier,
                    windowIDs: group.map(\.id),
                    isActive: group.contains { $0.pid == frontmostPID },
                    isMinimized: group.allSatisfy(\.isMinimized),
                    isHidden: group.allSatisfy { !$0.isVisible },
                    screenUUID: first.screenUUID
                )
            }
        }

        // Windows first, in the order they appeared; apps with nothing open
        // collect at the far end, out of the way.
        let windows = next.sorted { slot(for: $0.id) < slot(for: $1.id) }
        let idle = runningAppsWithoutWindows(excluding: Set(records.map(\.pid)))
            .sorted { slot(for: $0.id) < slot(for: $1.id) }

        // Publishing an equal array would rebuild every button for nothing.
        var combined = windows + idle

        // A button the user has renamed wears that name instead.
        for index in combined.indices {
            if let custom = CustomNames.shared.name(for: combined[index].id) {
                combined[index].title = custom
            }
        }
        CustomNames.shared.prune(keeping: Set(combined.map(\.id)))

        guard combined != items else { return }
        items = combined
    }

    /// The slot a button occupies, claimed on first sight.
    ///
    /// Entries are deliberately never removed: a window that briefly vanishes
    /// from a sweep — which is exactly what a flaky attribute read causes —
    /// comes back to the place it left rather than jumping to the end.
    private func slot(for id: String) -> Int {
        if let existing = slots[id] { return existing }
        slots[id] = nextSlot
        nextSlot += 1
        return slots[id]!
    }

    /// Apps that are running but own no windows.
    ///
    /// Closing the last window of a Mac app does not quit it — the app stays
    /// alive with nothing on screen, which is why the Dock keeps showing it
    /// with a dot underneath. A purely window-driven bar loses the app at that
    /// moment, so these keep their place, and clicking one activates the app
    /// the way clicking its Dock tile would.
    private func runningAppsWithoutWindows(excluding pidsWithWindows: Set<pid_t>) -> [TaskbarItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.processIdentifier != ownPID
                    && !$0.isTerminated
                    && !pidsWithWindows.contains($0.processIdentifier)
            }
            .map { app in
                TaskbarItem(
                    id: TaskbarItem.appID(app.processIdentifier),
                    title: app.localizedName ?? "Untitled",
                    pid: app.processIdentifier,
                    bundleIdentifier: app.bundleIdentifier,
                    windowIDs: [],
                    isActive: app.processIdentifier == frontmostPID,
                    isMinimized: false,
                    hasWindows: false,
                    screenUUID: nil
                )
            }
    }

    /// The degraded bar: every regular running app, no window titles, no
    /// per-window buttons. Needs no permission at all.
    private func rebuildFromRunningApps() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let next = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
            .map { app in
                TaskbarItem(
                    id: TaskbarItem.appID(app.processIdentifier),
                    title: app.localizedName ?? "Untitled",
                    pid: app.processIdentifier,
                    bundleIdentifier: app.bundleIdentifier,
                    windowIDs: [],
                    isActive: app.processIdentifier == frontmostPID,
                    isMinimized: false,
                    screenUUID: nil
                )
            }
        guard next != items else { return }
        items = next
    }

    /// The window records behind one button, in the order they were found.
    func records(for item: TaskbarItem) -> [WindowRecord] {
        item.windowIDs.compactMap { id in records.first { $0.id == id } }
    }

    func records(withID id: CGWindowID) -> WindowRecord? {
        records.first { $0.id == id }
    }

    var frontmostApplication: pid_t? { frontmostPID }

    /// The buttons one bar should show, in groups that the view separates.
    ///
    /// Grouping is by display, ordered left to right, so a combined bar reads
    /// the way the desk is laid out rather than in whatever order the windows
    /// were found.
    func itemGroups(forScreen uuid: String?) -> [[TaskbarItem]] {
        let taskbar = SettingsStore.shared.settings.taskbar
        let distribution = taskbar.windowDistribution
        let windowItems = items.filter(\.hasWindows)

        // Apps with nothing open are a standing list rather than a reflection
        // of what is on this display, so repeating them on every bar is mostly
        // noise. They collect on the main display unless asked otherwise.
        let showsIdle = taskbar.closedAppsPlacement == .everyDisplay || isPrimary(uuid)
        let idle = showsIdle ? items.filter { !$0.hasWindows } : []

        switch distribution {
        case .perDisplay:
            guard let uuid else { return [items].filter { !$0.isEmpty } }
            let mine = windowItems.filter { $0.screenUUID == nil || $0.screenUUID == uuid }
            return [mine, idle].filter { !$0.isEmpty }

        case .allOnMainDisplay:
            // NSScreen.main follows the keyboard, which would move the whole
            // bar's contents around as you click between displays. The primary
            // display — the one at the origin, with the menu bar — is what
            // "main display" means in System Settings, and it is the first.
            guard isPrimary(uuid) else {
                // The other displays keep showing their own windows; only the
                // main one gets the full picture.
                guard let uuid else { return [] }
                let mine = windowItems.filter { $0.screenUUID == nil || $0.screenUUID == uuid }
                return [mine, idle].filter { !$0.isEmpty }
            }
            return combinedGroups(windowItems, idle: idle)

        case .allOnEveryDisplay:
            return combinedGroups(windowItems, idle: idle)
        }
    }

    /// The display at the origin, with the menu bar — what System Settings
    /// calls the main display.
    ///
    /// Deliberately not `NSScreen.main`, which follows the keyboard and would
    /// move a bar's contents from one screen to another as you clicked between
    /// them.
    private func isPrimary(_ uuid: String?) -> Bool {
        guard let uuid else { return false }
        return NSScreen.screens.first.flatMap { ScreenIdentity(screen: $0)?.uuid } == uuid
    }

    private func combinedGroups(_ windowItems: [TaskbarItem], idle: [TaskbarItem]) -> [[TaskbarItem]] {
        let ordered = NSScreen.screens
            .sorted { $0.frame.minX < $1.frame.minX }
            .compactMap { ScreenIdentity(screen: $0)?.uuid }

        var groups = ordered.map { uuid in windowItems.filter { $0.screenUUID == uuid } }
        // Windows we could not place on any display still deserve a button.
        groups.append(windowItems.filter { $0.screenUUID == nil })
        groups.append(idle)
        return groups.filter { !$0.isEmpty }
    }

    /// The buttons one bar should show.
    func items(forScreen uuid: String?) -> [TaskbarItem] {
        guard SettingsStore.shared.settings.taskbar.showsOnAllDisplays, let uuid else { return items }
        return items.filter { $0.screenUUID == nil || $0.screenUUID == uuid }
    }
}
