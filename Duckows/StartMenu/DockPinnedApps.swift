import AppKit

/// The apps pinned to the macOS Dock, in the order the user arranged them.
///
/// Duckows hides the Dock, and a hidden Dock takes the user's carefully
/// arranged shortcuts with it. Reading them back means the Start menu can put
/// them front and centre instead, so nothing is lost by hiding it.
///
/// They live in `com.apple.dock` under `persistent-apps`, each entry a
/// dictionary whose `tile-data` → `file-data` → `_CFURLString` is the bundle's
/// URL. It is a documented-by-convention layout rather than an API, so every
/// step is optional and a change in shape costs the feature, not the app.
@MainActor
final class DockPinnedApps: ObservableObject {
    static let shared = DockPinnedApps()

    @Published private(set) var apps: [InstalledApp] = []

    private init() {
        reload()
        // The Dock broadcasts this whenever its preferences change, which is
        // how a newly pinned app shows up without a relaunch.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(dockPreferencesChanged),
            name: NSNotification.Name("com.apple.dock.prefchanged"),
            object: nil
        )
    }

    @objc private func dockPreferencesChanged() {
        reload()
    }

    func reload() {
        let urls = Self.pinnedURLs()
        apps = urls.compactMap { AppCatalog.makeApp(at: $0, allowAgents: true) }
    }

    private static func pinnedURLs() -> [URL] {
        guard let entries = CFPreferencesCopyAppValue(
            "persistent-apps" as CFString,
            "com.apple.dock" as CFString
        ) as? [[String: Any]] else { return [] }

        return entries.compactMap { entry in
            guard let tile = entry["tile-data"] as? [String: Any],
                  let file = tile["file-data"] as? [String: Any],
                  let string = file["_CFURLString"] as? String,
                  let url = URL(string: string) ?? URL(string: string, relativeTo: nil) else {
                return nil
            }
            // Entries are file URLs; anything else in there is not an app.
            guard url.isFileURL, url.pathExtension == "app" else { return nil }
            return url.standardizedFileURL
        }
    }
}
