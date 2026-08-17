import ApplicationServices
import Cocoa

/// Maps an accessibility element to the window id the rest of the system uses.
///
/// Private but present since 10.x and relied on by every window manager on the
/// platform; there is no public equivalent. It is the join between the AX world
/// (titles, actions) and the CoreGraphics world (geometry, z-order, census).
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin, failure-tolerant helpers over the AX C API.
///
/// Every call here is synchronous Mach IPC into another process, so all of it
/// belongs on `WindowScanner`'s serial queue — never the main thread.
enum AXBridge {
    /// The default messaging timeout is 6 seconds. One unresponsive app would
    /// otherwise stall the taskbar for six seconds per attribute read.
    static let systemTimeout: Float = 1.0
    static let perAppTimeout: Float = 0.35

    static func configureSystemTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), systemTimeout)
    }

    static func application(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, perAppTimeout)
        return element
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id = CGWindowID(0)
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    // MARK: - Attribute reads

    static func copyValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyValue(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copyValue(element, attribute) as? Bool
    }

    static func windows(of app: AXUIElement) -> [AXUIElement] {
        copyValue(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? []
    }

    /// Reads several attributes in one IPC round trip instead of one per value.
    ///
    /// Without `.stopOnError` a failed entry comes back as an `AXValue` of type
    /// `.axError` rather than being omitted, so each slot has to be checked —
    /// otherwise a failed size read silently decodes as 0×0.
    static func multipleValues(_ element: AXUIElement, _ attributes: [String]) -> [String: AnyObject] {
        var raw: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(
            element, attributes as CFArray, AXCopyMultipleAttributeOptions(), &raw
        )
        guard status == .success,
              let values = raw as? [AnyObject],
              values.count == attributes.count else {
            return [:]
        }

        var result: [String: AnyObject] = [:]
        for (attribute, value) in zip(attributes, values) {
            if let axValue = value as! AXValue?, AXValueGetType(axValue) == .axError {
                continue
            }
            result[attribute] = value
        }
        return result
    }

    static func point(_ value: AnyObject?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ value: AnyObject?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    /// AX reports a top-left origin; AppKit wants bottom-left, measured from the
    /// bottom of the primary display.
    static func appKitRect(origin: CGPoint, size: CGSize) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: origin.x,
                      y: primaryHeight - origin.y - size.height,
                      width: size.width,
                      height: size.height)
    }
}
