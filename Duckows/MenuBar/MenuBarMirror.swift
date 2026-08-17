import Combine
import Foundation

/// Keeps the scanner and the hider in step with the settings.
///
/// The two are deliberately separate objects — mirroring is safe and boring,
/// hiding leans on undocumented layout behaviour — and this is the only place
/// that knows hiding is meaningless without mirroring: pushing everything off
/// the menu bar without showing it anywhere would simply lose it.
@MainActor
final class MenuBarMirror {
    static let shared = MenuBarMirror()

    private var cancellable: AnyCancellable?

    private init() {}

    func start() {
        apply(SettingsStore.shared.settings.tray)
        cancellable = SettingsStore.shared.$settings
            // `@Published` fires from `willSet`, so a synchronous subscriber
            // reads the value being replaced.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in self?.apply(settings.tray) }
    }

    private func apply(_ tray: TraySettings) {
        if tray.mirrorsMenuBarItems {
            MenuBarItemRegistry.shared.start()
        } else {
            MenuBarItemRegistry.shared.stop()
        }
        MenuBarHider.shared.setEnabled(tray.mirrorsMenuBarItems && tray.hidesMirroredItems)
    }
}
