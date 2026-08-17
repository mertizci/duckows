import AppKit
import ApplicationServices

/// Geometry captured on the main thread and handed to the scanner, so the
/// scanner never touches `NSScreen` from its own queue.
struct ScanContext {
    let primaryMaxY: CGFloat
    let screens: [(uuid: String, frame: CGRect)]

    @MainActor
    static func current() -> ScanContext {
        let screens = NSScreen.screens.compactMap { screen -> (String, CGRect)? in
            guard let identity = ScreenIdentity(screen: screen) else { return nil }
            return (identity.uuid, screen.frame)
        }
        return ScanContext(
            primaryMaxY: NSScreen.screens.first?.frame.maxY ?? 0,
            screens: screens
        )
    }

    func screenUUID(for frame: CGRect) -> String? {
        screens
            .map { ($0.uuid, $0.frame.intersection(frame)) }
            .filter { !$0.1.isNull }
            .max { a, b in a.1.width * a.1.height < b.1.width * b.1.height }?
            .0
    }
}

/// Walks every running application's accessibility tree and returns the windows
/// worth putting on a taskbar.
///
/// Everything here runs on one serial queue. AX is not thread-safe, and a
/// concurrent queue would spawn a thread per blocked call the moment a single
/// application stopped responding.
final class WindowScanner {
    private let queue = DispatchQueue(label: "app.duckows.ax", qos: .userInitiated)

    /// Applications that stopped answering, and when to try them again.
    ///
    /// Without this one wedged app is re-tried on every sweep and pays the full
    /// messaging timeout each time.
    private var breaker: [pid_t: (failures: Int, retryAfter: Date)] = [:]

    /// Windows we have seen on screen at least once.
    ///
    /// This is what separates a real window from an app's internal phantom
    /// without depending on the window still describing itself: a minimized
    /// window may report neither a position nor a title — WhatsApp does exactly
    /// that — but it was on screen a moment ago, and that is enough.
    private var everVisible: Set<CGWindowID> = []

    private static let attributes = [
        kAXTitleAttribute as String,
        kAXRoleAttribute as String,
        kAXSubroleAttribute as String,
        kAXMinimizedAttribute as String,
        kAXPositionAttribute as String,
        kAXSizeAttribute as String,
        // Not exposed as a kAX… constant; this is the literal attribute name.
        "AXFullScreen"
    ]

    func scan(context: ScanContext, completion: @escaping @MainActor ([WindowRecord]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let records = self.performScan(context: context)
            Task { @MainActor in completion(records) }
        }
    }

    // MARK: - Scanning

    private func performScan(context: ScanContext) -> [WindowRecord] {
        let onScreen = Self.onScreenWindowIDs()
        var seen: Set<CGWindowID> = []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var records: [WindowRecord] = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ownPID,
                  !app.isTerminated else { continue }

            let pid = app.processIdentifier
            if let entry = breaker[pid], entry.retryAfter > Date() { continue }

            let element = AXBridge.application(pid: pid)
            let windows = AXBridge.windows(of: element)

            if windows.isEmpty, AXBridge.copyValue(element, kAXWindowsAttribute as String) == nil {
                noteFailure(pid)
                continue
            }
            breaker.removeValue(forKey: pid)

            for window in windows {
                if let id = AXBridge.windowID(of: window) {
                    seen.insert(id)
                    if onScreen.contains(id) { everVisible.insert(id) }
                }
                if let record = makeRecord(
                    window: window,
                    app: app,
                    context: context,
                    onScreen: onScreen
                ) {
                    records.append(record)
                }
            }
        }

        // Forget windows that no longer exist anywhere, so the set tracks
        // this session rather than growing forever.
        everVisible.formIntersection(seen)

        return records
    }

    private func makeRecord(
        window: AXUIElement,
        app: NSRunningApplication,
        context: ScanContext,
        onScreen: Set<CGWindowID>
    ) -> WindowRecord? {
        guard let id = AXBridge.windowID(of: window) else { return nil }

        let values = AXBridge.multipleValues(window, Self.attributes)

        // Only real, standard windows belong on a taskbar — not dialogs,
        // palettes, popovers or an app's hidden helper windows.
        let role = values[kAXRoleAttribute as String] as? String
        let subrole = values[kAXSubroleAttribute as String] as? String
        guard role == (kAXWindowRole as String),
              subrole == (kAXStandardWindowSubrole as String) else { return nil }

        let isMinimized = values[kAXMinimizedAttribute as String] as? Bool ?? false
        let isFullscreen = values["AXFullScreen"] as? Bool ?? false
        let isVisible = onScreen.contains(id)

        let rawTitle = (values[kAXTitleAttribute as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // AX also reports windows the window server does not show, and those
        // have to be filtered out — but "is it on screen" is the wrong test on
        // its own. A minimized window is legitimately absent from that list,
        // and so are the windows of an app hidden with cmd-H; the previous
        // version dropped both whenever the minimized flag failed to read,
        // which is precisely when a window is minimized.
        //
        // Keeping it requires only that we have reason to believe it is real:
        // it is on screen, it was on screen earlier, it says it is minimized,
        // or it still names itself. A phantom satisfies none of these.
        guard isVisible || everVisible.contains(id) || isMinimized || !rawTitle.isEmpty else {
            return nil
        }

        var frame = CGRect.zero
        if let origin = AXBridge.point(values[kAXPositionAttribute as String]),
           let size = AXBridge.size(values[kAXSizeAttribute as String]) {
            frame = CGRect(x: origin.x,
                           y: context.primaryMaxY - origin.y - size.height,
                           width: size.width,
                           height: size.height)
        }

        return WindowRecord(
            id: id,
            pid: app.processIdentifier,
            element: window,
            title: rawTitle.isEmpty ? (app.localizedName ?? "Untitled") : rawTitle,
            appName: app.localizedName ?? "",
            bundleIdentifier: app.bundleIdentifier,
            isMinimized: isMinimized,
            isFullscreen: isFullscreen,
            isVisible: isVisible,
            frame: frame,
            screenUUID: frame.isEmpty ? nil : context.screenUUID(for: frame)
        )
    }

    private func noteFailure(_ pid: pid_t) {
        let failures = (breaker[pid]?.failures ?? 0) + 1
        // 1s, 2s, 4s … capped at 30s.
        let backoff = min(pow(2.0, Double(failures - 1)), 30)
        breaker[pid] = (failures, Date().addingTimeInterval(backoff))
    }

    /// The window server's own census of ordinary on-screen windows.
    ///
    /// Cheap — one call, no per-app IPC — and it needs no Screen Recording
    /// permission because only geometry is read, never `kCGWindowName`.
    private static func onScreenWindowIDs() -> Set<CGWindowID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids: Set<CGWindowID> = []
        for info in infos {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            ids.insert(number)
        }
        return ids
    }
}
