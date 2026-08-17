import AppKit
import SwiftUI

/// Hosts one `TaskbarPanel` on one display and keeps its frame pinned to the
/// configured edge, including while auto-hiding.
@MainActor
final class TaskbarWindowController: NSObject, NSWindowDelegate {
    let screenIdentity: ScreenIdentity?

    private var panel: TaskbarPanel?
    private var screen: NSScreen
    private var isConcealed = false
    private var pendingTransition: Task<Void, Never>?

    init(screen: NSScreen) {
        self.screen = screen
        self.screenIdentity = ScreenIdentity(screen: screen)
        super.init()
    }

    func show() {
        if panel == nil {
            let hosting = NSHostingController(
                rootView: TaskbarView(screenUUID: screenIdentity?.uuid)
                    .environmentObject(SettingsStore.shared)
            )
            hosting.view.frame = revealedFrame

            let newPanel = TaskbarPanel(contentRect: revealedFrame)
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
        pendingTransition?.cancel()
        panel?.orderOut(nil)
    }

    func update(screen: NSScreen) {
        self.screen = screen
        updateFrame()
    }

    /// Re-applies geometry after a settings or display change.
    ///
    /// The concealed/revealed state is derived from where the pointer actually
    /// is, so turning auto-hide on hides the bar immediately instead of leaving
    /// it out until the next mouse movement.
    func updateFrame() {
        let autoHide = SettingsStore.shared.settings.taskbar.autoHide
        if autoHide {
            let pointer = NSEvent.mouseLocation
            isConcealed = !(revealedFrame.contains(pointer) || triggerZone.contains(pointer))
        } else {
            isConcealed = false
        }
        pendingTransition?.cancel()
        panel?.setFrame(isConcealed ? concealedFrame : revealedFrame, display: true)
    }

    // MARK: - Auto-hide

    func pointerMoved(to point: NSPoint) {
        guard SettingsStore.shared.settings.taskbar.autoHide else {
            if isConcealed { transition(toConcealed: false, after: 0) }
            return
        }

        let wantsRevealed = revealedFrame.contains(point) || triggerZone.contains(point)
        guard wantsRevealed == isConcealed else { return }

        transition(
            toConcealed: !wantsRevealed,
            after: wantsRevealed ? AutoHideMonitor.revealDelay : AutoHideMonitor.concealDelay
        )
    }

    private func transition(toConcealed concealed: Bool, after delay: TimeInterval) {
        pendingTransition?.cancel()
        pendingTransition = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            guard let self, let panel = self.panel else { return }
            self.isConcealed = concealed
            // Resolved before the animation block: the frames are main-actor
            // state and the animation closure is not actor-isolated.
            let target = concealed ? self.concealedFrame : self.revealedFrame
            // The completion-handler form is spelled out because in an async
            // context the bare trailing-closure call resolves to the `async`
            // overload, which would suspend this task for the animation.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: false)
            }, completionHandler: nil)
        }
    }

    // MARK: - Geometry

    private var thickness: CGFloat {
        SettingsStore.shared.settings.appearance.barThickness
    }

    private var revealedFrame: NSRect {
        let full = screen.frame
        switch SettingsStore.shared.settings.taskbar.edge {
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

    /// The bar slid off the edge, leaving only a sliver to catch the pointer.
    private var concealedFrame: NSRect {
        let offset = thickness - AutoHideMonitor.revealStrip
        var frame = revealedFrame
        switch SettingsStore.shared.settings.taskbar.edge {
        case .bottom: frame.origin.y -= offset
        case .top: frame.origin.y += offset
        }
        return frame
    }

    /// The band along the screen edge that counts as reaching for the bar.
    private var triggerZone: NSRect {
        let full = screen.frame
        switch SettingsStore.shared.settings.taskbar.edge {
        case .bottom:
            return NSRect(x: full.minX, y: full.minY,
                          width: full.width, height: AutoHideMonitor.triggerDepth)
        case .top:
            let inset = ScreenRegistry.shared.menuBarInset(for: screen)
            return NSRect(x: full.minX,
                          y: full.maxY - inset - AutoHideMonitor.triggerDepth,
                          width: full.width,
                          height: AutoHideMonitor.triggerDepth)
        }
    }
}
