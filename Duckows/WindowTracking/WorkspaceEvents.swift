import AppKit

/// Application-level events. AX observers report what happens *inside* an app;
/// these report apps appearing, leaving, and taking focus.
@MainActor
final class WorkspaceEvents {
    static let shared = WorkspaceEvents()

    private var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                if let app = Self.app(from: note), app.activationPolicy == .regular {
                    // A freshly launched app usually has no window yet, so the
                    // observer is what catches the first one appearing.
                    AXAppObserverCenter.shared.observe(pid: app.processIdentifier)
                }
                WindowRegistry.shared.setNeedsRescan(.structural)
            }
        }

        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                if let app = Self.app(from: note) {
                    AXAppObserverCenter.shared.stopObserving(pid: app.processIdentifier)
                }
                WindowRegistry.shared.setNeedsRescan(.structural)
            }
        }

        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                WindowRegistry.shared.setFrontmost(pid: Self.app(from: note)?.processIdentifier)
                WindowRegistry.shared.setNeedsRescan(.structural)
            }
        }

        for name: NSNotification.Name in [
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    WindowRegistry.shared.setNeedsRescan(.structural)
                }
            }
        }

        AXAppObserverCenter.shared.observeAllRunningApps()
        WindowRegistry.shared.setFrontmost(
            pid: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
    }

    private static func app(from note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }
}
