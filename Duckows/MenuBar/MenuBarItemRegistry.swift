import AppKit
import ApplicationServices

/// One app's menu bar extra, as mirrored into our bar.
///
/// Deliberately holds no `AXUIElement`. The element is re-resolved from the pid
/// at the moment it is pressed: menu bar extras come and go with their apps,
/// and a stale handle is the difference between a dead icon and a working one.
struct MirroredMenuBarItem: Identifiable, Equatable {
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    /// Which of that app's extras this is, for the handful of apps with two.
    let index: Int

    var id: String { "\(bundleIdentifier ?? "pid:\(pid)")#\(index)" }
}

/// Finds the menu bar extras belonging to other apps.
///
/// The list comes from Accessibility — every application element carries an
/// `AXExtrasMenuBar` whose children are its status items. That needs no
/// permission beyond the one Duckows already has, and unlike screen-scraping
/// the menu bar it survives the notch, wallpaper changes and Liquid Glass.
///
/// Apple's own items are left out: Wi-Fi, Bluetooth, Sound, Battery and the
/// clock are the widgets this tray already provides natively, so mirroring
/// them would show everything twice.
@MainActor
final class MenuBarItemRegistry: ObservableObject {
    static let shared = MenuBarItemRegistry()

    @Published private(set) var items: [MirroredMenuBarItem] = []

    /// AX is not thread-safe and must never be called from the main thread —
    /// one hung app would otherwise freeze the bar.
    private let queue = DispatchQueue(label: "app.duckows.menubar", qos: .utility)
    private var poll: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard poll == nil else { return }
        rescan()

        // Apps add their status item some time after launching, so the
        // notification is a prompt to look again shortly, not an answer.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    MenuBarItemRegistry.shared.rescan()
                }
            })
        }

        // The safety net: an app can add or drop an item at any time without
        // launching or quitting.
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.rescan()
            }
        }
    }

    func stop() {
        poll?.cancel()
        poll = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        items = []
    }

    func rescan() {
        let candidates = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String?, String)? in
            guard let bundle = app.bundleIdentifier else { return nil }
            guard bundle != Bundle.main.bundleIdentifier else { return nil }
            // Apple's own extras are either replaced by a native widget here or
            // removable in System Settings; mirroring them duplicates the tray.
            guard !bundle.hasPrefix("com.apple.") else { return nil }
            return (app.processIdentifier, bundle, app.localizedName ?? bundle)
        }

        queue.async {
            var found: [(MirroredMenuBarItem, CGFloat)] = []
            for (pid, bundle, name) in candidates {
                for (index, position) in Self.extraPositions(pid: pid).enumerated() {
                    found.append((
                        MirroredMenuBarItem(pid: pid, bundleIdentifier: bundle,
                                            appName: name, index: index),
                        position
                    ))
                }
            }
            // Left to right, the order they read in the menu bar.
            let ordered = found.sorted { $0.1 < $1.1 }.map(\.0)
            Task { @MainActor in
                guard MenuBarItemRegistry.shared.items != ordered else { return }
                MenuBarItemRegistry.shared.items = ordered
            }
        }
    }

    // MARK: - Pressing

    /// Clicks the real item.
    ///
    /// The menu it opens belongs to the owning app and appears at the top of
    /// the screen, against its own status item — no API moves it. So if the
    /// items are being hidden they have to be put back first, and left there
    /// until the menu closes.
    func press(_ item: MirroredMenuBarItem) {
        let wasHiding = MenuBarHider.shared.isHiding
        if wasHiding { MenuBarHider.shared.setConcealed(false) }

        queue.asyncAfter(deadline: .now() + (wasHiding ? 0.15 : 0)) {
            guard let element = Self.element(for: item) else {
                if wasHiding { Task { @MainActor in MenuBarHider.shared.setConcealed(true) } }
                return
            }
            AXUIElementPerformAction(element, kAXPressAction as CFString)
            guard wasHiding else { return }
            Self.waitUntilDismissed(element)
            Task { @MainActor in MenuBarHider.shared.setConcealed(true) }
        }
    }

    /// Blocks on the scan queue until the item stops being highlighted.
    ///
    /// `AXSelected` is true for as long as the item's menu is open. Some items
    /// show a popover instead and never report selected at all, hence the grace
    /// period before giving up rather than snapping the menu bar shut under a
    /// menu the user just opened.
    private static func waitUntilDismissed(_ element: AXUIElement) {
        let deadline = Date().addingTimeInterval(120)
        var everSelected = false
        var graceRemaining = 8  // 8 × 250ms before deciding it never highlighted

        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            var value: AnyObject?
            let status = AXUIElementCopyAttributeValue(element, "AXSelected" as CFString, &value)
            guard status == .success else { return }  // the item went away
            let selected = (value as? Bool) ?? false

            if selected {
                everSelected = true
            } else if everSelected {
                return
            } else {
                graceRemaining -= 1
                if graceRemaining <= 0 { return }
            }
        }
    }

    // MARK: - Accessibility

    private static func element(for item: MirroredMenuBarItem) -> AXUIElement? {
        let extras = self.extras(pid: item.pid)
        guard item.index < extras.count else { return nil }
        return extras[item.index]
    }

    private static func extras(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXBridge.perAppTimeout)
        var bar: AnyObject?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString,
                                            &children) == .success else { return [] }
        return children as? [AXUIElement] ?? []
    }

    /// The x of each of an app's extras, used only for ordering.
    private static func extraPositions(pid: pid_t) -> [CGFloat] {
        extras(pid: pid).map { element in
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString,
                                                &value) == .success,
                  let point = AXBridge.point(value) else { return .greatestFiniteMagnitude }
            return point.x
        }
    }
}
