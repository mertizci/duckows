import SwiftUI

struct GeneralSettingsPage: View {
    @EnvironmentObject private var store: SettingsStore
    @ObservedObject private var launch = LaunchAtLoginController.shared

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

            SettingsCard(
                title: "Window space",
                subtitle: "Whether maximized windows are allowed to slide underneath the bar."
            ) {
                SettingsOptionRow(title: "Reserve space") {
                    Picker("", selection: Binding(
                        get: { store.settings.general.spaceReservation },
                        set: { store.setSpaceReservation($0) }
                    )) {
                        ForEach(SpaceReservationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }

                Text(store.settings.general.spaceReservation.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                StatusBanner(
                    style: .info,
                    message: "Not wired up yet — the bar currently floats above your windows. "
                        + "This setting takes effect in a later release."
                )
            }
        }
        .onAppear { launch.refresh() }
    }
}
