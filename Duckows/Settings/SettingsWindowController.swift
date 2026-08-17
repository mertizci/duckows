import AppKit
import SwiftUI

/// Hosts the settings window.
///
/// The hosting controller is built once rather than rebuilt on every `show()`,
/// so reopening the window keeps the page you were on and its scroll position.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show(section: SettingsSection? = nil) {
        if let section {
            SettingsSelection.shared.section = section
        }

        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(SettingsStore.shared)
            )
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Duckows Settings"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 900, height: 640))
            newWindow.minSize = NSSize(width: 860, height: 600)
            newWindow.center()
            newWindow.delegate = self
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        }

        window?.makeKeyAndOrderFront(nil)

        // Duckows is an LSUIElement agent, so it is .accessory and cannot take
        // keyboard focus. Promote it to a regular app while a real window is up
        // — otherwise the window opens behind everything with dead controls —
        // and demote on close so we stay out of the Dock and the app switcher.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
