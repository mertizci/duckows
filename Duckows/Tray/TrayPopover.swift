import AppKit
import SwiftUI

/// The panel a tray widget opens when you click it.
///
/// SwiftUI's `.popover` is not usable here: it wants a key window, and the bar
/// is a `.nonactivatingPanel` that deliberately never becomes one — the same
/// reason the taskbar buttons pop an `NSMenu` instead of using `.contextMenu`.
/// A menu is the wrong shape for a slider or a calendar grid, so the tray gets
/// its own panel, built like the Start menu's but without the activation: no
/// widget here needs the keyboard, and activating would steal focus from
/// whatever the user is actually working in.
@MainActor
final class TrayPopoverController: NSObject {
    static let shared = TrayPopoverController()

    private var panel: TrayPopoverPanel?
    private var hosting: NSHostingController<AnyView>?
    /// Which widget the open panel belongs to, so clicking the same one closes
    /// it and clicking a different one swaps the contents.
    private var openWidget: String?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?

    private override init() { super.init() }

    func toggle(widget: String, anchor: NSView?, content: @autoclosure () -> AnyView) {
        if openWidget == widget {
            close()
        } else {
            show(widget: widget, anchor: anchor, content: content())
        }
    }

    func close() {
        removeMonitors()
        panel?.orderOut(nil)
        openWidget = nil
    }

    private func show(widget: String, anchor: NSView?, content: AnyView) {
        let padded = AnyView(content.padding(14).fixedSize())

        if let hosting {
            hosting.rootView = padded
        } else {
            let controller = NSHostingController(rootView: padded)
            let newPanel = TrayPopoverPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 1, height: 1)))
            newPanel.contentViewController = controller
            hosting = controller
            panel = newPanel
        }

        guard let panel, let hosting else { return }
        // `fittingSize` is only meaningful once the hosting view has laid out
        // the new root, which it does not do until asked.
        hosting.view.layoutSubtreeIfNeeded()
        panel.setFrame(frame(for: hosting.view.fittingSize, anchor: anchor), display: true)
        panel.orderFront(nil)
        openWidget = widget
        installMonitors()
    }

    /// Centred on the widget, on the far side of the bar from the screen edge,
    /// clamped so a wide popover on the last widget stays on the display.
    ///
    /// Falls back to the pointer if there is no anchor view: a popover a few
    /// pixels off is still usable, a button that does nothing is not.
    private func frame(for size: NSSize, anchor: NSView?) -> NSRect {
        let gap: CGFloat = 6
        guard let window = anchor?.window, let screen = window.screen,
              let anchor else {
            let point = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
                    ?? NSScreen.main else {
                return NSRect(origin: point, size: size)
            }
            let thickness = SettingsStore.shared.settings.appearance.barThickness
            let x = min(max(point.x - size.width / 2, screen.visibleFrame.minX + 8),
                        screen.visibleFrame.maxX - size.width - 8)
            let y = SettingsStore.shared.settings.taskbar.edge == .bottom
                ? screen.frame.minY + thickness + gap
                : screen.frame.maxY - ScreenRegistry.shared.menuBarInset(for: screen)
                    - thickness - gap - size.height
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }
        let onScreen = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))

        let x = min(max(onScreen.midX - size.width / 2, screen.visibleFrame.minX + 8),
                    screen.visibleFrame.maxX - size.width - 8)
        let y = SettingsStore.shared.settings.taskbar.edge == .bottom
            ? onScreen.maxY + gap
            : onScreen.minY - gap - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - Dismissal

    private func installMonitors() {
        guard outsideClickMonitor == nil else { return }
        // A global monitor never sees clicks on our own windows, which is
        // exactly what "clicked outside" means here.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { _ in
            Task { @MainActor in TrayPopoverController.shared.close() }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == 53 else { return event }  // Escape
            Task { @MainActor in TrayPopoverController.shared.close() }
            return nil
        }
    }

    private func removeMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        outsideClickMonitor = nil
        escapeMonitor = nil
    }
}

/// Non-activating and never key: the tray has nothing to type into, so taking
/// focus would only interrupt the app the user is in.
final class TrayPopoverPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
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

    override var canBecomeKey: Bool { false }
}

/// Holds onto the widget's backing view so the popover can be positioned
/// against it. A class, because SwiftUI hands `makeNSView` a fresh view
/// whenever it feels like it and the button's action needs the current one.
@MainActor
final class TrayAnchorBox {
    weak var view: NSView?
}

/// A zero-content view whose only job is to have a frame in screen
/// coordinates. `hitTest` returns nil so it never comes between the pointer
/// and the button it is measuring.
struct TrayAnchor: NSViewRepresentable {
    let box: TrayAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }

    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
