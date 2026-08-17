import AppKit

/// Pushes other apps' menu bar extras out of sight.
///
/// There is no API for this, and there is no private one either — the only
/// thing that works is a property of the layout itself. macOS packs status
/// items from the right edge leftwards and simply stops drawing the ones that
/// no longer fit, so an item of our own that is absurdly wide displaces
/// everything to its left past the edge of the usable area.
///
/// That is the same mechanism Bartender and Ice use, and it comes with the
/// same caveats, which the settings page states rather than hides:
///
/// - It only moves items to the **left** of ours, so our spacer has to sit at
///   the right-hand end. The position is persisted under the key AppKit itself
///   uses for `autosaveName`, which is undocumented.
/// - Apple's own items (Control Center, the clock, Spotlight) are anchored to
///   the right and are not affected. They come off the menu bar through System
///   Settings, and most of them are already native widgets in this tray.
/// - Nothing here is written to disk on another app's behalf and nothing
///   survives us: the spacer dies with the process, and the menu bar lays
///   itself back out. A crash cannot leave the user's menu bar broken.
@MainActor
final class MenuBarHider {
    static let shared = MenuBarHider()

    private(set) var isEnabled = false
    /// Whether the items are pushed out right now. Distinct from `isEnabled`
    /// because a mirrored item being clicked has to bring them back briefly.
    private(set) var isHiding = false

    private var spacer: NSStatusItem?

    private static let autosaveName = "duckows-spacer"
    /// Wider than any menu bar; anything to the left of it is off the end.
    private static let concealedLength: CGFloat = 10_000

    private init() {}

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            install()
            setConcealed(true)
        } else {
            setConcealed(false)
            if let spacer { NSStatusBar.system.removeStatusItem(spacer) }
            spacer = nil
        }
    }

    func setConcealed(_ concealed: Bool) {
        guard isEnabled || !concealed else {
            isHiding = false
            spacer?.length = 0
            return
        }
        isHiding = concealed
        spacer?.length = concealed ? Self.concealedLength : 0
    }

    private func install() {
        guard spacer == nil else { return }
        // AppKit reads the saved position before the item is placed, so this
        // has to be written first. Zero puts us as far right as a third-party
        // item is allowed to go, which is what makes everything else fall to
        // our left and off the end.
        UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position \(Self.autosaveName)")

        let item = NSStatusBar.system.statusItem(withLength: 0)
        item.autosaveName = Self.autosaveName
        item.behavior = []
        // Nothing to see and nothing to click: the spacer is structure, not UI.
        item.button?.image = nil
        item.button?.title = ""
        item.button?.isEnabled = false
        spacer = item
    }
}
