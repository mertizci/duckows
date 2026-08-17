import SwiftUI

/// The live bar: observes the store and the window registry, and hands the
/// current state to `TaskbarChrome`.
struct TaskbarView: View {
    let screenUUID: String?

    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject private var registry = WindowRegistry.shared
    @ObservedObject private var permissions = PermissionMonitor.shared

    var body: some View {
        TaskbarChrome(
            appearance: settingsStore.settings.appearance,
            taskbar: settingsStore.settings.taskbar,
            items: registry.items(forScreen: screenUUID),
            needsAccessibility: !permissions.isAccessibilityTrusted
        )
        .frame(height: settingsStore.settings.appearance.barThickness)
    }
}
