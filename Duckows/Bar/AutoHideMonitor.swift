import AppKit

/// Watches the pointer so concealed bars know when to slide back out.
///
/// One monitor serves every display. `.mouseMoved` needs no Accessibility
/// permission, unlike key events, so this works before the user has granted
/// anything.
@MainActor
final class AutoHideMonitor {
    static let shared = AutoHideMonitor()

    /// How much of the bar stays on screen while concealed. It has to be wide
    /// enough for the pointer to land on, but invisible enough not to read as a
    /// stripe along the edge.
    static let revealStrip: CGFloat = 2

    /// How far from the edge the pointer counts as "reaching for the bar".
    static let triggerDepth: CGFloat = 4

    static let revealDelay: TimeInterval = 0.12
    static let concealDelay: TimeInterval = 0.45

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { _ in
            Task { @MainActor in
                TaskbarPresenter.shared.pointerMoved(to: NSEvent.mouseLocation)
            }
        }
        // A global monitor never sees events delivered to our own windows, so
        // without this the bar would conceal itself the moment the pointer
        // moved onto it.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            Task { @MainActor in
                TaskbarPresenter.shared.pointerMoved(to: NSEvent.mouseLocation)
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isRunning = false
    }
}
