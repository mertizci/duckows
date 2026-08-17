import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            TaskbarPresenter.shared.start()

            UpdateController.shared.consumePostUpdateNoticeIfNeeded()
            if SettingsStore.shared.settings.general.checksForUpdatesAutomatically {
                UpdateController.shared.checkForUpdatesOnLaunch()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Duckows will mutate the system Dock from phase 5 onward; restoring it
        // here is what makes every exit path safe, so the hook exists from the
        // start. Settings are flushed synchronously because the debounced write
        // may not have landed yet.
        MainActor.assumeIsolated {
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
