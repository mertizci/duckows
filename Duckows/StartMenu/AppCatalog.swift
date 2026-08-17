import AppKit

struct InstalledApp: Identifiable, Equatable {
    let id: String          // bundle identifier
    let name: String
    let url: URL
    let category: AppCategory

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
}

/// The applications on this Mac, grouped the way the Start menu shows them.
///
/// Deliberately a directory scan rather than a Spotlight query. Spotlight types
/// *any* directory whose name ends in `.app` as an application bundle, so
/// `kMDItemContentTypeTree == "com.apple.application-bundle"` comes back with
/// hundreds of false positives — per-app cache folders under
/// `~/Library/HTTPStorages` named after reverse-DNS bundle ids among them.
/// Walking the handful of real install locations is both faster and honest.
@MainActor
final class AppCatalog: ObservableObject {
    static let shared = AppCatalog()

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoaded = false

    private static let roots = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications"
    ]

    private init() {}

    func loadIfNeeded() {
        guard !isLoaded else { return }
        reload()
    }

    func reload() {
        Task.detached(priority: .utility) {
            let found = Self.scan()
            await MainActor.run {
                self.apps = found
                self.isLoaded = true
            }
        }
    }

    /// Grouped for display, categories in a stable order with Other last.
    var grouped: [(category: AppCategory, apps: [InstalledApp])] {
        let byCategory = Dictionary(grouping: apps, by: \.category)
        return AppCategory.displayOrder.compactMap { category in
            guard let list = byCategory[category], !list.isEmpty else { return nil }
            return (category, list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    func app(forBundleIdentifier id: String) -> InstalledApp? {
        apps.first { $0.id == id }
    }

    // MARK: - Scanning

    private nonisolated static func scan() -> [InstalledApp] {
        var byIdentifier: [String: InstalledApp] = [:]

        for root in roots {
            let url = URL(fileURLWithPath: root)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                // skipsPackageDescendants is load-bearing: without it a scan of
                // /Applications walks *into* Xcode.app and returns the dozens of
                // helper apps embedded in it.
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" {
                guard let app = makeApp(at: entry) else { continue }
                // Prefer the shallowest path when the same app appears twice.
                if let existing = byIdentifier[app.id],
                   existing.url.pathComponents.count <= app.url.pathComponents.count {
                    continue
                }
                byIdentifier[app.id] = app
            }
        }

        return byIdentifier.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// - Parameter allowAgents: keep `LSUIElement` bundles. False for the
    ///   catalogue, where an agent has no business in a launcher — but true for
    ///   the Dock's pinned apps, because the user put it there on purpose.
    ///   macOS 26's own `Apps.app` is exactly this case.
    nonisolated static func makeApp(at url: URL, allowAgents: Bool = false) -> InstalledApp? {
        guard let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              // The one check that rejects the fake ".app" directories: a real
              // application bundle has an executable.
              bundle.executableURL != nil else { return nil }

        let info = bundle.infoDictionary ?? [:]
        if !allowAgents {
            if info["LSUIElement"] as? Bool == true { return nil }
            if info["LSBackgroundOnly"] as? Bool == true { return nil }
        }

        // displayName honours CFBundleDisplayName and localisation, which
        // reading CFBundleName directly does not.
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")

        return InstalledApp(
            id: identifier,
            name: name,
            url: url,
            category: AppCategory(
                rawCategory: info["LSApplicationCategoryType"] as? String,
                bundleURL: url,
                bundleIdentifier: identifier
            )
        )
    }
}
