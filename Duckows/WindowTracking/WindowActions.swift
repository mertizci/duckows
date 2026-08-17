import AppKit
import ApplicationServices

/// What a taskbar button actually does.
///
/// Each verb is one or more synchronous AX calls, so they run off the main
/// thread: an app that is busy would otherwise freeze the bar for the full
/// messaging timeout on every click.
enum WindowActions {
    private static let queue = DispatchQueue(label: "app.duckows.ax.actions", qos: .userInitiated)

    /// Brings a window forward.
    ///
    /// The order is not interchangeable. Un-minimizing has to happen first or
    /// there is nothing to raise; activating the app before raising is what
    /// makes the window come to the front rather than merely to the front of
    /// its own app; and setting it main afterwards is what gives it the
    /// keyboard.
    static func raise(_ record: WindowRecord) {
        let element = record.element
        let pid = record.pid
        let wasMinimized = record.isMinimized

        queue.async {
            // An app hidden with cmd-H has to be unhidden before any of its
            // windows can come forward, and unhiding is an AppKit call rather
            // than an AX one.
            Task { @MainActor in
                let app = NSRunningApplication(processIdentifier: pid)
                if app?.isHidden == true { app?.unhide() }
            }

            if wasMinimized {
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }

            let app = AXBridge.application(pid: pid)
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)

            Task { @MainActor in
                // AX frontmost alone does not always move keyboard focus when
                // the target is on another Space.
                NSRunningApplication(processIdentifier: pid)?.activate()
                WindowRegistry.shared.setNeedsRescan(.structural)
            }
        }
    }

    static func minimize(_ record: WindowRecord) {
        let element = record.element
        queue.async {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            Task { @MainActor in WindowRegistry.shared.setNeedsRescan(.structural) }
        }
    }

    /// Clicking the button of the window you are already in puts it away, the
    /// way a Windows taskbar behaves.
    static func toggle(_ record: WindowRecord, isFrontmost: Bool) {
        // Only put a window away when it is genuinely in front of you. A
        // minimized or hidden window belonging to the frontmost app would
        // otherwise be "minimized" again and appear not to respond.
        if isFrontmost && record.isVisible && !record.isMinimized {
            minimize(record)
        } else {
            raise(record)
        }
    }

    static func close(_ record: WindowRecord) {
        let element = record.element
        queue.async {
            guard let button = AXBridge.copyValue(element, kAXCloseButtonAttribute as String) else { return }
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            Task { @MainActor in WindowRegistry.shared.setNeedsRescan(.structural) }
        }
    }

    /// Fills the display the window is on, up to the taskbar.
    ///
    /// Deliberately not `AXPress` on the zoom button: what that does is up to
    /// the app, and in several it means "fit to content" rather than "fill the
    /// screen". Setting the frame gives the Windows behaviour every time.
    @MainActor
    static func maximize(_ record: WindowRecord) {
        guard let uuid = record.screenUUID else { return }

        // `geometry` is nil while the bar auto-hides or that display is showing
        // something full screen — the bar is holding no space then, so the
        // window is entitled to everything below the menu bar.
        let target = TaskbarPresenter.shared.geometry(forScreen: uuid)?.usable
            ?? NSScreen.screens
                .first { ScreenIdentity(screen: $0)?.uuid == uuid }?
                .visibleFrame

        guard let target else { return }
        setFrame(target, on: record)
    }

    @MainActor
    static func move(_ record: WindowRecord, toScreen screen: NSScreen) {
        guard let identity = ScreenIdentity(screen: screen) else { return }
        let target = TaskbarPresenter.shared.geometry(forScreen: identity.uuid)?.usable
            ?? screen.visibleFrame

        // Keep the window's size, just re-centre it on the other display, and
        // shrink only if it genuinely does not fit.
        var frame = record.frame
        frame.size.width = min(frame.width, target.width)
        frame.size.height = min(frame.height, target.height)
        frame.origin = CGPoint(x: target.midX - frame.width / 2,
                               y: target.midY - frame.height / 2)
        setFrame(frame, on: record)
    }

    @MainActor
    private static func setFrame(_ frame: CGRect, on record: WindowRecord) {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let element = record.element
        queue.async {
            var origin = CGPoint(x: frame.minX, y: primaryMaxY - frame.maxY)
            var size = CGSize(width: frame.width, height: frame.height)

            func apply(_ attribute: String, _ value: AXValue?) {
                guard let value else { return }
                AXUIElementSetAttributeValue(element, attribute as CFString, value)
            }

            // Size, position, size again — and the repetition is the point.
            // A resize is clamped against where the window currently is, so a
            // window sitting near the bottom right can only grow as far as that
            // corner allows, and a single pass leaves it short of filling the
            // screen. Moving it first and then resizing has the mirror problem.
            apply(kAXSizeAttribute as String, AXValueCreate(.cgSize, &size))
            apply(kAXPositionAttribute as String, AXValueCreate(.cgPoint, &origin))
            apply(kAXSizeAttribute as String, AXValueCreate(.cgSize, &size))

            Task { @MainActor in WindowRegistry.shared.setNeedsRescan(.structural) }
        }
    }

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    /// The Dock's "Force Quit", including its confirmation — this kills work in
    /// progress, so it should never happen on a stray click.
    @MainActor
    static func forceQuit(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        let name = app.localizedName ?? "this app"

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Force \(name) to quit?"
        alert.informativeText = "Anything you have not saved will be lost."
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")

        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        NSApp.setActivationPolicy(previousPolicy)

        guard response == .alertFirstButtonReturn else { return }
        app.forceTerminate()
    }

    @MainActor
    static func revealInFinder(pid: pid_t) {
        guard let url = applicationURL(pid: pid) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// The `.app` a running process belongs to.
    ///
    /// `NSRunningApplication.bundleURL` is not always one. Steam updates itself
    /// into `~/Library/Application Support/Steam/Steam.AppBundle/Steam`, a
    /// bundle with no `.app` extension, and handing that to LaunchServices
    /// opens a Finder window on the folder instead of launching anything.
    /// Asking LaunchServices to resolve the bundle identifier gives the app the
    /// user actually installed.
    @MainActor
    static func applicationURL(pid: pid_t) -> URL? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        if let identifier = app.bundleIdentifier,
           let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return resolved
        }
        guard let url = app.bundleURL, url.pathExtension == "app" else { return nil }
        return url
    }

    static func hide(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.hide()
    }
}
