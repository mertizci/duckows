import AppKit
import CoreGraphics

/// One window belonging to another application.
///
/// Carries both handles on purpose: the `AXUIElement` is how you read a title
/// or raise the window, and the `CGWindowID` is how the window server names it,
/// which is what makes reconciliation against a `CGWindowList` census possible.
struct WindowRecord: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let element: AXUIElement
    var title: String
    var appName: String
    var bundleIdentifier: String?
    var isMinimized: Bool
    var frame: CGRect
    /// Sticky: a minimized window reports a garbage position, so the last known
    /// display is kept rather than letting it jump to another screen's bar.
    var screenUUID: String?

    /// `element` is deliberately excluded — identity is the window id, and two
    /// AXUIElement handles to the same window are not necessarily equal.
    static func == (lhs: WindowRecord, rhs: WindowRecord) -> Bool {
        lhs.id == rhs.id
            && lhs.pid == rhs.pid
            && lhs.title == rhs.title
            && lhs.isMinimized == rhs.isMinimized
            && lhs.frame == rhs.frame
            && lhs.screenUUID == rhs.screenUUID
    }
}

/// What one taskbar button draws. Per-window and per-app grouping collapse into
/// the same type so the view never has to branch on the grouping mode.
struct TaskbarItem: Identifiable, Equatable {
    let id: String
    let title: String
    let pid: pid_t
    let bundleIdentifier: String?
    let windowIDs: [CGWindowID]
    let isActive: Bool
    let isMinimized: Bool
    let screenUUID: String?

    static func windowID(_ id: CGWindowID) -> String { "w:\(id)" }
    static func appID(_ pid: pid_t) -> String { "a:\(pid)" }
}

/// Application icons, resolved once per bundle rather than per redraw.
///
/// `NSWorkspace.icon(forFile:)` hits Launch Services, which is far too slow to
/// call from a SwiftUI `body`.
@MainActor
enum AppIconProvider {
    private static var cache: [String: NSImage] = [:]

    static func icon(pid: pid_t, bundleIdentifier: String?, size: CGFloat) -> NSImage? {
        let key = bundleIdentifier ?? "pid:\(pid)"
        if let cached = cache[key] {
            return resized(cached, to: size)
        }
        guard let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon else {
            return nil
        }
        cache[key] = icon
        return resized(icon, to: size)
    }

    private static func resized(_ image: NSImage, to size: CGFloat) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: size, height: size)
        return copy
    }
}
