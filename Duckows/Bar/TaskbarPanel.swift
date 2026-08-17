import AppKit

/// The taskbar window for one display.
///
/// `.nonactivatingPanel` is the load-bearing part: clicking a taskbar button
/// must activate the *target* application, so Duckows itself must never become
/// frontmost as a side effect of the click.
final class TaskbarPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // canJoinAllSpaces: one panel serves every Space rather than being
        //   rebuilt on each switch.
        // stationary: Mission Control and Exposé leave it in place instead of
        //   flying it away with the user's windows.
        // ignoresCycle: keeps it out of cmd-` and the Window menu.
        // fullScreenAuxiliary: allowed to coexist with another app's
        //   full-screen space instead of forcing it out.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        isFloatingPanel = true

        // Must come *after* isFloatingPanel: setting that property forces the
        // level back to .floating (3), which is below the Dock at 20 — the bar
        // would end up underneath the very thing it replaces.
        //
        // The Dock is level 20 and the menu bar 24, so 21 covers the Dock and
        // every ordinary window while leaving the menu bar, menu-bar extras and
        // Control Center on top.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)

        // NSPanel defaults this to true, which would hide the taskbar the
        // instant the user clicked anything else — i.e. always.
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isRestorable = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .none
        // Only take key focus when a subview genuinely needs it; plain clicks
        // on buttons must not steal focus from the user's app.
        becomesKeyOnlyIfNeeded = true
    }

    // Borderless windows refuse key status by default, which would make the
    // Start menu's search field unusable.
    override var canBecomeKey: Bool { true }

    // Never take "main" away from the window the user is actually working in.
    override var canBecomeMain: Bool { false }
}
