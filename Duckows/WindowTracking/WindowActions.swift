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
        if isFrontmost && !record.isMinimized {
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

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    static func hide(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.hide()
    }
}
