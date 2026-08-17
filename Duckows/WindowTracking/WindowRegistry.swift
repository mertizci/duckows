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
        scanner.scan(context: context) { [weak self] records in
            guard let self else { return }
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
                    isActive: record.pid == frontmostPID && !record.isMinimized,
                    isMinimized: record.isMinimized,
                    screenUUID: record.screenUUID
                )
            }
        case .byApp:
            var order: [pid_t] = []
            var grouped: [pid_t: [WindowRecord]] = [:]
            for record in records {
                if grouped[record.pid] == nil { order.append(record.pid) }
                grouped[record.pid, default: []].append(record)
            }
            next = order.compactMap { pid in
                guard let group = grouped[pid], let first = group[0] as WindowRecord? else { return nil }
                return TaskbarItem(
                    id: TaskbarItem.appID(pid),
                    title: first.appName.isEmpty ? first.title : first.appName,
                    pid: pid,
                    bundleIdentifier: first.bundleIdentifier,
                    windowIDs: group.map(\.id),
                    isActive: pid == frontmostPID,
                    isMinimized: group.allSatisfy(\.isMinimized),
                    screenUUID: first.screenUUID
                )
            }
        }

        // Publishing an equal array would rebuild every button for nothing.
        let combined = next + runningAppsWithoutWindows(excluding: Set(records.map(\.pid)))
        guard combined != items else { return }
        items = combined
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

    /// The buttons one bar should show.
    func items(forScreen uuid: String?) -> [TaskbarItem] {
        guard SettingsStore.shared.settings.taskbar.showsOnAllDisplays, let uuid else { return items }
        return items.filter { $0.screenUUID == nil || $0.screenUUID == uuid }
    }
}
