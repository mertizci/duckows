import AppKit
import ApplicationServices

/// Opens things on the display you asked from.
///
/// macOS has no way to say "open on this screen": an app puts its window
/// wherever it last was, so clicking Network on one monitor happily opens
/// System Settings on another. There is no API for it because the window does
/// not exist yet at the moment of asking.
///
/// So the window is moved after the fact. The app is opened, then its window
/// is watched for and nudged onto the target display if it came up elsewhere.
enum WindowPlacement {
    /// How long to keep watching. Cold-starting a large app takes a while, and
    /// giving up too early is worse than a late nudge.
    private static let attempts = 30
    private static let interval = Duration.milliseconds(160)

    @MainActor
    static func open(_ url: URL, bundleIdentifier: String?, onScreen uuid: String?) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            if let error {
                NSLog("Duckows: could not open \(url.lastPathComponent) – \(error.localizedDescription)")
                return
            }
            guard let uuid else { return }
            let identifier = app?.bundleIdentifier ?? bundleIdentifier
            Task { @MainActor in
                follow(bundleIdentifier: identifier, pid: app?.processIdentifier, onScreen: uuid)
            }
        }
    }

    /// For things opened by URL rather than by bundle — a
    /// `x-apple.systempreferences:` link, or a folder handed to Finder.
    @MainActor
    static func openURL(_ url: URL, expecting bundleIdentifier: String, onScreen uuid: String?) {
        NSWorkspace.shared.open(url)
        guard let uuid else { return }
        follow(bundleIdentifier: bundleIdentifier, pid: nil, onScreen: uuid)
    }

    @MainActor
    static func follow(bundleIdentifier: String?, pid: pid_t?, onScreen uuid: String) {
        guard PermissionMonitor.shared.isAccessibilityTrusted else { return }
        guard let target = NSScreen.screens.first(where: { ScreenIdentity(screen: $0)?.uuid == uuid })
        else { return }

        let targetFrame = target.frame
        let usable = target.visibleFrame
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0

        Task.detached(priority: .userInitiated) {
            for _ in 0..<attempts {
                try? await Task.sleep(for: interval)

                let running: NSRunningApplication? = await MainActor.run {
                    if let pid { return NSRunningApplication(processIdentifier: pid) }
                    guard let bundleIdentifier else { return nil }
                    return NSRunningApplication
                        .runningApplications(withBundleIdentifier: bundleIdentifier).first
                }
                guard let running, !running.isTerminated else { continue }

                if moveMainWindow(
                    pid: running.processIdentifier,
                    targetFrame: targetFrame,
                    usable: usable,
                    primaryMaxY: primaryMaxY
                ) {
                    return
                }
            }
        }
    }

    /// Returns true once a window has been found and dealt with — either it was
    /// already on the right display, or it has been moved there.
    private nonisolated static func moveMainWindow(
        pid: pid_t,
        targetFrame: CGRect,
        usable: CGRect,
        primaryMaxY: CGFloat
    ) -> Bool {
        let app = AXBridge.application(pid: pid)

        // The main window is the one the user is looking at; fall back to the
        // first standard window for apps that do not report one.
        let candidate = AXBridge.copyValue(app, kAXMainWindowAttribute as String)
            .map { $0 as! AXUIElement }
            ?? AXBridge.windows(of: app).first { window in
                AXBridge.string(window, kAXSubroleAttribute as String) == (kAXStandardWindowSubrole as String)
            }
        guard let window = candidate,
              let origin = AXBridge.point(AXBridge.copyValue(window, kAXPositionAttribute as String)),
              let size = AXBridge.size(AXBridge.copyValue(window, kAXSizeAttribute as String)),
              size.width > 0, size.height > 0 else { return false }

        let frame = CGRect(x: origin.x, y: primaryMaxY - origin.y - size.height,
                           width: size.width, height: size.height)
        if targetFrame.intersects(frame),
           targetFrame.intersection(frame).width * targetFrame.intersection(frame).height
            > frame.width * frame.height * 0.5 {
            return true  // already mostly on the right display
        }

        // Centre it, then pull it fully inside the usable area so nothing lands
        // under the menu bar or off the edge.
        var placed = CGRect(
            x: usable.midX - size.width / 2,
            y: usable.midY - size.height / 2,
            width: min(size.width, usable.width),
            height: min(size.height, usable.height)
        )
        placed.origin.x = min(max(placed.minX, usable.minX), usable.maxX - placed.width)
        placed.origin.y = min(max(placed.minY, usable.minY), usable.maxY - placed.height)

        var newOrigin = CGPoint(x: placed.minX, y: primaryMaxY - placed.maxY)
        if let value = AXValueCreate(.cgPoint, &newOrigin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
        return true
    }
}
