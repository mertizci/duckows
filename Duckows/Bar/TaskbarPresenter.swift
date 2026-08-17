import AppKit
import Combine

/// Creates and tears down one taskbar per display, and re-pins them whenever
/// the display arrangement or the user's settings change.
@MainActor
final class TaskbarPresenter: ObservableObject {
    static let shared = TaskbarPresenter()

    private var controllers: [ObjectIdentifier: TaskbarWindowController] = [:]
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
        let live = Set(screens.map { ObjectIdentifier($0) })

        // Drop controllers for displays that went away.
        for (key, controller) in controllers where !live.contains(key) {
            controller.hide()
            controllers.removeValue(forKey: key)
        }

        for screen in screens {
            let key = ObjectIdentifier(screen)
            let identity = ScreenIdentity(screen: screen)
            let isDisabled = !settings.showsOnAllDisplays && screen != NSScreen.main
                || identity.map { settings.disabledDisplayUUIDs.contains($0.uuid) } ?? false

            if isDisabled {
                controllers[key]?.hide()
                controllers.removeValue(forKey: key)
                continue
            }

            if let existing = controllers[key] {
                existing.update(screen: screen)
            } else {
                let controller = TaskbarWindowController(screen: screen)
                controllers[key] = controller
                controller.show()
            }
        }
    }

    private func refreshFrames() {
        controllers.values.forEach { $0.updateFrame() }
    }
}
