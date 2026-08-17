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

        // Settings changes can both move the bars and change which displays get
        // one, so this runs the full reconcile rather than only re-pinning
        // frames — otherwise turning off "show on all displays" would do
        // nothing until the next display event.
        //
        // `.receive(on:)` is load-bearing, not tidiness. @Published emits from
        // `willSet`, so a synchronous subscriber runs *before* the property is
        // actually updated: the reconcile would read the previous settings and
        // apply them, leaving every change one step behind. Switching the bar
        // to the top did nothing until you switched it back.
        SettingsStore.shared.$settings
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.synchronize(with: ScreenRegistry.shared.screens)
                DockController.shared.apply()
                // The bar may have moved, so what counts as maximized changed
                // with it.
                MaximizeGuard.shared.reset()
            }
            .store(in: &cancellables)

        // A full-screen window covers its whole display and cannot be resized
        // out of the bar's way, so the bar is what moves.
        WindowRegistry.shared.$fullscreenScreenUUIDs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uuids in self?.applyFullscreen(uuids) }
            .store(in: &cancellables)

        synchronize(with: ScreenRegistry.shared.screens)
        AutoHideMonitor.shared.start()
    }

    private func applyFullscreen(_ uuids: Set<String>) {
        for (identity, controller) in controllers {
            if uuids.contains(identity.uuid) {
                controller.hide()
            } else {
                controller.show()
            }
        }
    }

    func stop() {
        AutoHideMonitor.shared.stop()
        controllers.values.forEach { $0.hide() }
        controllers.removeAll()
    }

    /// Forwarded from `AutoHideMonitor`; each bar decides for itself whether
    /// the pointer is reaching for it.
    func pointerMoved(to point: NSPoint) {
        controllers.values.forEach { $0.pointerMoved(to: point) }
    }

    /// The bar's strip and the area left over on one display.
    ///
    /// Nil while auto-hide is on or that display is showing a full-screen
    /// window: in neither case is the bar holding any space.
    func geometry(forScreen uuid: String) -> ScreenGeometry? {
        guard !SettingsStore.shared.settings.taskbar.autoHide,
              !WindowRegistry.shared.fullscreenScreenUUIDs.contains(uuid),
              let controller = controllers[ScreenIdentity(uuid: uuid)] else { return nil }
        return ScreenGeometry(bar: controller.barFrame, usable: controller.usableFrame)
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

}
