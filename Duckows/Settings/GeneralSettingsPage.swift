import SwiftUI

struct GeneralSettingsPage: View {
    @EnvironmentObject private var store: SettingsStore
    @ObservedObject private var launch = LaunchAtLoginController.shared
    @ObservedObject private var permissions = PermissionMonitor.shared

    var body: some View {
        SettingsDetailScaffold(section: .general) {
            SettingsCard(title: "Startup") {
                SettingsToggleRow(
                    title: "Open Duckows at login",
                    subtitle: "Starts the taskbar automatically when you log in.",
                    isOn: Binding(
                        get: { launch.isEnabled },
                        set: { launch.setEnabled($0) }
                    ),
                    isEnabled: !launch.isTranslocated
                )

                if launch.isTranslocated {
                    StatusBanner(
                        style: .warning,
                        message: "Duckows is running from a temporary location, so macOS will not "
                            + "open it at login. Move it to your Applications folder."
                    )
                } else if launch.needsUserApproval {
                    StatusBanner(
                        style: .warning,
                        message: "macOS is holding the Duckows login item for your approval.",
                        actionTitle: "Open Login Items",
                        action: { launch.openLoginItemsSettings() }
                    )
                } else if let error = launch.lastError {
                    StatusBanner(style: .warning, message: error.message)
                }
            }

            SettingsCard(title: "Updates") {
                SettingsToggleRow(
                    title: "Check for updates automatically",
                    subtitle: "Looks for a new release on GitHub each time Duckows starts.",
                    isOn: Binding(
                        get: { store.settings.general.checksForUpdatesAutomatically },
                        set: { store.setChecksForUpdatesAutomatically($0) }
                    )
                )

                HStack {
                    Spacer()
                    Button("Check Now") {
                        UpdateController.shared.checkForUpdates(silent: false)
                    }
                }
            }

            SettingsCard(title: "Desktop") {
                SettingsToggleRow(
                    title: "Hide the macOS Dock",
                    subtitle: "Restored exactly as you had it when Duckows quits.",
                    isOn: Binding(
                        get: { store.settings.general.hidesSystemDock },
                        set: { store.setHidesSystemDock($0) }
                    ),
                    isEnabled: DockController.shared.isAvailable
                )

                if !DockController.shared.isAvailable {
                    StatusBanner(
                        style: .warning,
                        message: "This version of macOS does not expose the Dock's auto-hide switch, "
                            + "so Duckows cannot hide it for you."
                    )
                }
            }
        }
        .onAppear { launch.refresh() }
    }
}
