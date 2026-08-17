import AppKit
import Carbon

enum PowerAction: String, CaseIterable, Identifiable {
    case sleep
    case lockScreen
    case logOut
    case restart
    case shutDown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleep:      return "Sleep"
        case .lockScreen: return "Lock Screen"
        case .logOut:     return "Log Out"
        case .restart:    return "Restart"
        case .shutDown:   return "Shut Down"
        }
    }

    var symbolName: String {
        switch self {
        case .sleep:      return "moon"
        case .lockScreen: return "lock"
        case .logOut:     return "rectangle.portrait.and.arrow.right"
        case .restart:    return "arrow.clockwise"
        case .shutDown:   return "power"
        }
    }
}

/// Sleep, restart, shut down and friends.
///
/// These go to `loginwindow` as Core Events, which is Apple's own documented
/// mechanism (QA1134). It is better than scripting System Events: loginwindow
/// owns the standard confirmation sheet, so the user sees the dialog they
/// already recognise, and there is no second app in the automation chain.
enum PowerActionService {
    static func perform(_ action: PowerAction) {
        switch action {
        case .sleep:      send(kAESleep)
        case .logOut:     send(kAEReallyLogOut)
        case .restart:    send(kAERestart)
        case .shutDown:   send(kAEShutDown)
        case .lockScreen: lockScreen()
        }
    }

    private static func send(_ eventID: AEEventID) {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kSystemProcess))
        var target = AEAddressDesc()
        var event = AppleEvent()
        var reply = AppleEvent()

        var status = AECreateDesc(typeProcessSerialNumber, &psn,
                                  MemoryLayout.size(ofValue: psn), &target)
        guard status == noErr else { return }
        defer { AEDisposeDesc(&target) }

        status = AECreateAppleEvent(kCoreEventClass, eventID, &target,
                                    AEReturnID(kAutoGenerateReturnID),
                                    AETransactionID(kAnyTransactionID), &event)
        guard status == noErr else { return }
        defer { AEDisposeDesc(&event); AEDisposeDesc(&reply) }

        // kAEDefaultTimeout is an Int constant; AESend wants an Int32.
        status = AESend(&event, &reply, AESendMode(kAENoReply),
                        AESendPriority(kAENormalPriority), Int32(kAEDefaultTimeout), nil, nil)
        if status != noErr {
            // -1743 is errAEEventNotPermitted: the user declined the Automation
            // prompt, and only System Settings can undo that.
            NSLog("Duckows: power action refused (\(status))")
            if status == -1743 {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
                )!)
            }
        }
    }

    /// `SACLockScreenImmediate` is what the Apple menu's own Lock Screen item
    /// calls. Private, but stable for a decade — and resolved at runtime, so a
    /// future removal falls back to the keyboard shortcut instead of crashing.
    ///
    /// `open -a ScreenSaverEngine` is deliberately not used: it stopped
    /// reliably *locking* anything around Sonoma.
    private static func lockScreen() {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY) {
            defer { dlclose(handle) }
            if let symbol = dlsym(handle, "SACLockScreenImmediate") {
                typealias LockFn = @convention(c) () -> Int32
                if unsafeBitCast(symbol, to: LockFn.self)() == 0 { return }
            }
        }
        sendControlCommandQ()
    }

    /// Control-Command-Q, the system shortcut for Lock Screen.
    private static func sendControlCommandQ() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let flags: CGEventFlags = [.maskCommand, .maskControl]
        let keyQ: CGKeyCode = 12
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyQ, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyQ, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
