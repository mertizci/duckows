import AppKit
import SwiftUI

/// The panel that opens from the Start button.
@MainActor
final class StartMenuPanelController: NSObject, NSWindowDelegate {
    static let shared = StartMenuPanelController()

    private var panel: StartMenuPanel?
    private var outsideClickMonitor: Any?
    private var localMonitor: Any?

    private static let size = NSSize(width: 460, height: 540)

    private override init() {
        super.init()
    }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle(anchorScreen: NSScreen?) {
        if isOpen {
            close()
        } else {
            open(anchorScreen: anchorScreen)
        }
    }

    func open(anchorScreen: NSScreen?) {
        AppCatalog.shared.loadIfNeeded()
        DockPinnedApps.shared.reload()

        if panel == nil {
            let hosting = NSHostingController(rootView: StartMenuView())
            let newPanel = StartMenuPanel(
                contentRect: NSRect(origin: .zero, size: Self.size)
            )
            newPanel.contentViewController = hosting
            newPanel.delegate = self
            panel = newPanel
        }

        panel?.setFrame(frame(on: anchorScreen ?? NSScreen.main), display: true)
        panel?.makeKeyAndOrderFront(nil)
        // The search field needs keyboard focus, and an agent app cannot take
        // it without being promoted first.
        NSApp.activate(ignoringOtherApps: true)
        installDismissMonitors()
    }

    func close() {
        removeDismissMonitors()
        panel?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    // MARK: - Placement

    private func frame(on screen: NSScreen?) -> NSRect {
        guard let screen else { return NSRect(origin: .zero, size: Self.size) }
        let visible = screen.visibleFrame
        let settings = SettingsStore.shared.settings
        let thickness = settings.appearance.barThickness
        let gap: CGFloat = 8

        let x = min(max(screen.frame.minX + 12, visible.minX), visible.maxX - Self.size.width - 12)
        let y: CGFloat
        switch settings.taskbar.edge {
        case .bottom:
            y = screen.frame.minY + thickness + gap
        case .top:
            let inset = ScreenRegistry.shared.menuBarInset(for: screen)
            y = screen.frame.maxY - inset - thickness - gap - Self.size.height
        }

        // Clamp so a tall panel on a short display stays on screen.
        let clampedY = min(max(y, visible.minY + 8), visible.maxY - Self.size.height - 8)
        return NSRect(x: x, y: clampedY, width: Self.size.width, height: Self.size.height)
    }

    // MARK: - Dismissal

    private func installDismissMonitors() {
        guard outsideClickMonitor == nil else { return }

        // A global monitor never sees clicks on our own windows, which is
        // exactly what "clicked outside" means here.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { _ in
            Task { @MainActor in StartMenuPanelController.shared.close() }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // 53 is Escape.
            if event.keyCode == 53 {
                Task { @MainActor in StartMenuPanelController.shared.close() }
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        outsideClickMonitor = nil
        localMonitor = nil
    }
}

/// Borderless, non-activating, but able to become key so the search field
/// works.
final class StartMenuPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the taskbar itself, below real menus.
        level = .popUpMenu
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
}
