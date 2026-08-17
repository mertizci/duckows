import AppKit
import Combine

/// A display identity that survives sleep, cable swaps and reboots.
///
/// `CGDirectDisplayID` is reused by the system, so persisting per-display
/// settings against it silently moves them to a different monitor. The display
/// UUID does not get reused.
struct ScreenIdentity: Hashable, Codable {
    let uuid: String

    init(uuid: String) {
        self.uuid = uuid
    }

    init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        uuid = CFUUIDCreateString(nil, cfUUID) as String
    }
}

/// Tracks the connected displays and republishes them on a debounce.
///
/// `didChangeScreenParameters` fires five to ten times during a display wake or
/// a resolution change; rebuilding a window per screen on each one is visible
/// as flicker, so the burst is coalesced.
@MainActor
final class ScreenRegistry: ObservableObject {
    static let shared = ScreenRegistry()

    @Published private(set) var screens: [NSScreen] = NSScreen.screens

    private var debounceTask: Task<Void, Never>?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func identity(for screen: NSScreen) -> ScreenIdentity? {
        ScreenIdentity(screen: screen)
    }

    /// The height the menu bar occupies on `screen`, or zero on displays that
    /// do not show one.
    func menuBarInset(for screen: NSScreen) -> CGFloat {
        max(0, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    @objc private func screenParametersChanged() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.screens = NSScreen.screens
        }
    }
}
