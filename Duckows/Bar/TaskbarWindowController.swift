import AppKit
import SwiftUI

/// Hosts one `TaskbarPanel` on one display and keeps its frame pinned to the
/// configured edge.
@MainActor
final class TaskbarWindowController: NSObject, NSWindowDelegate {
    let screenIdentity: ScreenIdentity?

    private var panel: TaskbarPanel?
    private var screen: NSScreen

    init(screen: NSScreen) {
        self.screen = screen
        self.screenIdentity = ScreenIdentity(screen: screen)
        super.init()
    }

    func show() {
        if panel == nil {
            let hosting = NSHostingController(
                rootView: TaskbarView().environmentObject(SettingsStore.shared)
            )
            hosting.view.frame = frame(for: screen)

            let newPanel = TaskbarPanel(contentRect: frame(for: screen))
            newPanel.contentViewController = hosting
            newPanel.delegate = self
            panel = newPanel
        }

        updateFrame()
        // orderFrontRegardless rather than makeKeyAndOrderFront: the bar must
        // appear without Duckows becoming the active application.
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Re-pins the panel after a settings change, a resolution change, or the
    /// display being moved in the arrangement.
    func update(screen: NSScreen) {
        self.screen = screen
        updateFrame()
    }

    func updateFrame() {
        panel?.setFrame(frame(for: screen), display: true)
    }

    private func frame(for screen: NSScreen) -> NSRect {
        let settings = SettingsStore.shared.settings
        let thickness = settings.appearance.barThickness
        let full = screen.frame

        switch settings.taskbar.edge {
        case .bottom:
            return NSRect(x: full.minX, y: full.minY, width: full.width, height: thickness)
        case .top:
            // Sit directly beneath the menu bar rather than over it.
            let inset = ScreenRegistry.shared.menuBarInset(for: screen)
            return NSRect(x: full.minX,
                          y: full.maxY - inset - thickness,
                          width: full.width,
                          height: thickness)
        }
    }
}
