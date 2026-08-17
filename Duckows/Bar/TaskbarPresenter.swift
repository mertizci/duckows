import AppKit
import Combine

/// Creates and tears down one taskbar per display, and re-pins them whenever
/// the display arrangement or the user's settings change.
@MainActor
final class TaskbarPresenter: ObservableObject {
    static let shared = TaskbarPresenter()

    /// Keyed by display UUID, not by the NSScreen object. AppKit hands out fresh
    /// NSScreen instances after every display configuration change, so keying on
    /// object identity would tear down and rebuild every bar on each resolution
    /// change or hot-plug — visible as a flash.
    private var controllers: [ScreenIdentity: TaskbarWindowController] = [:]
    private var cancellables: Set<AnyCancellable> = []

    private init() {}

    func start() {
        ScreenRegistry.shared.$screens
            .sink { [weak self] screens in self?.synchronize(with: screens) }
            .store(in: &cancellables)

        // Geometry and appearance both live in settings, so any change may move
        // the bars. Re-pinning is cheap enough not to need finer filtering.
        SettingsStore.shared.$settings
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshFrames() }
            .store(in: &cancellables)

        synchronize(with: ScreenRegistry.shared.screens)
    }

    func stop() {
        controllers.values.forEach { $0.hide() }
        controllers.removeAll()
    }

    private func synchronize(with screens: [NSScreen]) {
        let settings = SettingsStore.shared.settings.taskbar

        // A display with no resolvable UUID (rare, seen with some virtual
        // displays) gets no bar rather than an unmanageable one.
        let identified = screens.compactMap { screen -> (ScreenIdentity, NSScreen)? in
            ScreenIdentity(screen: screen).map { ($0, screen) }
        }
        let live = Set(identified.map(\.0))

        // Drop controllers for displays that went away.
        for (key, controller) in controllers where !live.contains(key) {
            controller.hide()
            controllers.removeValue(forKey: key)
        }

        for (identity, screen) in identified {
            let isOnlyMainAllowed = !settings.showsOnAllDisplays && screen != NSScreen.main
            let isExplicitlyDisabled = settings.disabledDisplayUUIDs.contains(identity.uuid)

            if isOnlyMainAllowed || isExplicitlyDisabled {
                controllers[identity]?.hide()
                controllers.removeValue(forKey: identity)
                continue
            }

            if let existing = controllers[identity] {
                existing.update(screen: screen)
            } else {
                let controller = TaskbarWindowController(screen: screen)
                controllers[identity] = controller
                controller.show()
            }
        }
    }

    private func refreshFrames() {
        controllers.values.forEach { $0.updateFrame() }
    }
}
