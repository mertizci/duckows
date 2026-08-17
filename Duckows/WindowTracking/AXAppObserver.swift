import AppKit
import ApplicationServices

/// Callbacks stay deliberately trivial: they mark the registry dirty and
/// return. The debounce decides when to actually rescan, and every expensive
/// AX read happens on the scanner's queue rather than in here.
private let axNotificationCallback: AXObserverCallback = { _, _, notification, _ in
    let name = notification as String
    let reason: WindowRegistry.Reason =
        name == (kAXTitleChangedNotification as String) ? .title : .structural
    Task { @MainActor in
        WindowRegistry.shared.setNeedsRescan(reason)
    }
}

/// Keeps one `AXObserver` per running application so window changes arrive as
/// events instead of being discovered by polling.
final class AXAppObserverCenter {
    static let shared = AXAppObserverCenter()

    private let queue = DispatchQueue(label: "app.duckows.ax.observers", qos: .utility)
    private var observers: [pid_t: AXObserver] = [:]

    private static let notifications = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification
    ].map { $0 as String }

    private init() {}

    func observe(pid: pid_t) {
        // Subscribing is synchronous IPC per notification, so it never runs on
        // the main thread: an unresponsive app would freeze the UI for the full
        // messaging timeout, once per notification.
        queue.async { [weak self] in
            guard let self, self.observers[pid] == nil else { return }

            var observer: AXObserver?
            guard AXObserverCreate(pid, axNotificationCallback, &observer) == .success,
                  let observer else { return }

            let element = AXBridge.application(pid: pid)
            var subscribed = false
            for notification in Self.notifications {
                let status = AXObserverAddNotification(observer, element, notification as CFString, nil)
                // .notificationUnsupported / .notImplemented mean this app will
                // never send it, so there is nothing to retry. Anything else is
                // just this app being busy right now.
                if status == .success || status == .notificationAlreadyRegistered {
                    subscribed = true
                }
            }
            guard subscribed else { return }

            self.observers[pid] = observer
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
    }

    func stopObserving(pid: pid_t) {
        queue.async { [weak self] in
            guard let observer = self?.observers.removeValue(forKey: pid) else { return }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
    }

    func observeAllRunningApps() {
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map(\.processIdentifier)
        pids.forEach(observe)
    }
}
