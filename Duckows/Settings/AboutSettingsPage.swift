import SwiftUI

struct AboutSettingsPage: View {
    @ObservedObject private var updater = UpdateController.shared
    @ObservedObject private var registry = WindowRegistry.shared
    @ObservedObject private var permissions = PermissionMonitor.shared

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        SettingsDetailScaffold(section: .about) {
            SettingsCard(title: "Duckows") {
                HStack(spacing: 14) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Duckows").font(.system(size: 15, weight: .semibold))
                        Text("Version \(updater.currentVersion) (\(buildNumber))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("A Windows-style taskbar for macOS.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Link("GitHub", destination: URL(string: "https://github.com/mertizci/duckows")!)
                    Link("Report an issue",
                         destination: URL(string: "https://github.com/mertizci/duckows/issues")!)
                    Spacer()
                    Button("Check for Updates…") {
                        updater.checkForUpdates(silent: false)
                    }
                }
                .font(.system(size: 11))
            }

            SettingsCard(
                title: "Diagnostics",
                subtitle: "A sweep reads every running app's window list over IPC — the one thing "
                    + "here that can quietly get slow."
            ) {
                SettingsOptionRow(title: "Last window sweep") {
                    Text(registry.lastScanDuration > 0
                         ? String(format: "%.0f ms · %d windows",
                                  registry.lastScanDuration * 1000, registry.items.count)
                         : "—")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                SettingsOptionRow(title: "Accessibility") {
                    Text(permissions.isAccessibilityTrusted ? "Granted" : "Not granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(permissions.isAccessibilityTrusted ? .green : .orange)
                }
            }

            SettingsCard(title: "Configuration") {
                Text("Settings are stored as JSON at ~/Library/Application Support/Duckows/config.json")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Reveal in Finder") {
                        let url = FileManager.default
                            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("Duckows/config.json")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
    }
}
