import SwiftUI

/// The live bar: observes the store and hands the current settings to
/// `TaskbarChrome`.
struct TaskbarView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        TaskbarChrome(
            appearance: settingsStore.settings.appearance,
            taskbar: settingsStore.settings.taskbar
        )
        .frame(height: settingsStore.settings.appearance.barThickness)
    }
}
