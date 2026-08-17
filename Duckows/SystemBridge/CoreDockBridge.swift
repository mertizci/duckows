import Foundation

/// The Dock's own auto-hide switch, the same one System Settings flips.
///
/// `CoreDock*` lives in HIServices and is not public API, so every symbol is
/// resolved at runtime rather than linked: if Apple removes one, Duckows loses
/// the ability to hide the Dock instead of failing to launch.
///
/// The alternative — writing `com.apple.dock` defaults and `killall Dock` — is
/// worse: it restarts the Dock (a visible flash, minimized window tiles get
/// rebuilt) and edits the user's preferences from outside the preferences
/// system.
enum CoreDockBridge {
    private typealias GetAutoHideFn = @convention(c) () -> Bool
    private typealias SetAutoHideFn = @convention(c) (Bool) -> Void

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
        RTLD_LAZY
    )

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let getAutoHide = symbol("CoreDockGetAutoHideEnabled", as: GetAutoHideFn.self)
    private static let setAutoHide = symbol("CoreDockSetAutoHideEnabled", as: SetAutoHideFn.self)

    /// False when the symbols are missing, so callers can tell the user the
    /// feature is unavailable rather than silently doing nothing.
    static var isAvailable: Bool { getAutoHide != nil && setAutoHide != nil }

    static var isAutoHideEnabled: Bool? {
        getAutoHide?()
    }

    @discardableResult
    static func setAutoHideEnabled(_ enabled: Bool) -> Bool {
        guard let setAutoHide else { return false }
        setAutoHide(enabled)
        return true
    }
}
