import Foundation

/// Owns the on-disk configuration at
/// `~/Library/Application Support/Duckows/config.json`.
///
/// Every mutation goes through `updateSettings(_:)` so there is exactly one
/// place that marks the file dirty, and writes are coalesced — a slider drag
/// produces one write instead of hundreds.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var settings: AppSettings

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var saveTask: Task<Void, Never>?

    private var configURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = appSupport.appendingPathComponent("Duckows", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("config.json")
    }

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Duckows", isDirectory: true)
            .appendingPathComponent("config.json")
        settings = Self.load(from: url, decoder: decoder) ?? .default
    }

    private static func load(from url: URL, decoder: JSONDecoder) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            // Every field decodes leniently, so reaching here means the file is
            // genuinely malformed. Keep the original so the user can inspect it
            // rather than silently overwriting it with defaults.
            NSLog("Duckows: config.json could not be read – \(error.localizedDescription)")
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("config.corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            return nil
        }
    }

    // MARK: - Mutation

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        scheduleSave()
    }

    func setBarEdge(_ edge: BarEdge) {
        updateSettings { $0.taskbar.edge = edge }
    }

    func setBarStyle(_ style: BarStyle) {
        updateSettings { $0.appearance.style = style }
    }

    func setTintHex(_ hex: String?) {
        updateSettings { $0.appearance.tintHex = hex }
    }

    func setTintOpacity(_ value: Double) {
        updateSettings { $0.appearance.tintOpacity = value.clamped(to: 0...1) }
    }

    func setBackgroundOpacity(_ value: Double) {
        updateSettings { $0.appearance.backgroundOpacity = value.clamped(to: 0.15...1) }
    }

    func setBarThickness(_ value: Double) {
        updateSettings { $0.appearance.barThickness = value.clamped(to: 32...80) }
    }

    func setCornerRadius(_ value: Double) {
        updateSettings { $0.appearance.cornerRadius = value.clamped(to: 0...24) }
    }

    func setGrouping(_ mode: GroupingMode) {
        updateSettings { $0.taskbar.grouping = mode }
    }

    func setWindowDistribution(_ mode: WindowDistribution) {
        updateSettings { $0.taskbar.windowDistribution = mode }
    }

    func setClosedAppsPlacement(_ placement: ClosedAppsPlacement) {
        updateSettings { $0.taskbar.closedAppsPlacement = placement }
    }

    func setShowsWindowTitles(_ shows: Bool) {
        updateSettings { $0.taskbar.showsWindowTitles = shows }
    }

    func setKeepsMaximizedWindowsClear(_ enabled: Bool) {
        updateSettings { $0.general.keepsMaximizedWindowsClear = enabled }
    }

    func setHidesSystemDock(_ enabled: Bool) {
        updateSettings { $0.general.hidesSystemDock = enabled }
    }

    func setChecksForUpdatesAutomatically(_ enabled: Bool) {
        updateSettings { $0.general.checksForUpdatesAutomatically = enabled }
    }

    /// The Dock snapshot is written through the same funnel, but must reach
    /// disk immediately — if the process dies before a debounced write lands,
    /// the user's Dock settings are unrecoverable.
    func setDockRestoreState(_ state: DockRestoreState?) {
        settings.dockRestore = state
        saveNow()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes synchronously. Called on app termination and for the Dock
    /// snapshot, where a debounce would be a data-loss bug.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            let data = try encoder.encode(settings)
            try data.write(to: configURL, options: .atomic)
        } catch {
            NSLog("Duckows: failed to save settings – \(error.localizedDescription)")
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
