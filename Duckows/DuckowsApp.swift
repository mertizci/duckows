import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            PermissionMonitor.shared.refresh()
            // Before anything else touches the Dock: repair a previous run
            // that died with it hidden.
            DockController.shared.recoverFromCrashIfNeeded()
            TaskbarPresenter.shared.start()
            DockController.shared.apply()

            // Started regardless of the Accessibility grant: without it the
            // registry falls back to a per-app bar, and the workspace events
            // are what notice the grant arriving.
            WindowRegistry.shared.start()
            WorkspaceEvents.shared.start()
            MenuBarMirror.shared.start()
            PermissionsOnboardingWindowController.shared.showIfNeeded()

            NotificationCenter.default.addObserver(
                forName: .duckowsAccessibilityChanged, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    AXAppObserverCenter.shared.observeAllRunningApps()
                    WindowRegistry.shared.setNeedsRescan(.structural)
                }
            }

            // Order matters: the notice has to win. Running the launch check
            // as well would replace "Updated to 0.2.0" with a spinner before
            // the user had a chance to read it.
            let showedUpdateNotice = UpdateController.shared.consumePostUpdateNoticeIfNeeded()
            if !showedUpdateNotice,
               SettingsStore.shared.settings.general.checksForUpdatesAutomatically {
                UpdateController.shared.checkForUpdatesOnLaunch()
            }
        }
    }

    /// Duckows has no Dock icon, so `open -a Duckows` on a running instance is
    /// how people ask it for something. Settings is the only sensible answer.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            SettingsWindowController.shared.show()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Duckows will mutate the system Dock from phase 5 onward; restoring it
        // here is what makes every exit path safe, so the hook exists from the
        // start. Settings are flushed synchronously because the debounced write
        // may not have landed yet.
        MainActor.assumeIsolated {
            DockController.shared.restore()
            // Not strictly needed — the spacer dies with the process and the
            // menu bar lays itself back out — but putting the items back before
            // we go means the user never sees a menu bar mid-reflow.
            MenuBarHider.shared.setEnabled(false)
            SettingsStore.shared.saveNow()
        }
    }
}

@main
struct DuckowsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore = SettingsStore.shared
    @StateObject private var updateController = UpdateController.shared

    var body: some Scene {
        // A menu bar item is the only control surface until the Settings window
        // lands. An LSUIElement app has no Dock tile and no menu of its own, so
        // without this there is no way to quit.
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(settingsStore)
                .environmentObject(updateController)
        } label: {
            Image(systemName: "rectangle.bottomthird.inset.filled")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContentView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var updateController: UpdateController

    var body: some View {
        Text("Duckows \(updateController.currentVersion)")

        Divider()

        Button("Settings…") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",")

        Picker("Bar position", selection: edgeBinding) {
            ForEach(BarEdge.allCases) { edge in
                Text(edge.displayName).tag(edge)
            }
        }

        Button("Check for Updates…") {
            updateController.checkForUpdates(silent: false)
        }

        Divider()

        Button("Quit Duckows") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var edgeBinding: Binding<BarEdge> {
        Binding(
            get: { settingsStore.settings.taskbar.edge },
            set: { settingsStore.setBarEdge($0) }
        )
    }
}
