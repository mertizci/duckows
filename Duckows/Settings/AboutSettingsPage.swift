import SwiftUI

struct AboutSettingsPage: View {
    @ObservedObject private var updater = UpdateController.shared

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
