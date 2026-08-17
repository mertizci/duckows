import Foundation

/// Which screen edge the taskbar occupies.
enum BarEdge: String, Codable, CaseIterable, Identifiable {
    case bottom
    case top

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bottom: return "Bottom"
        case .top: return "Top"
        }
    }
}

/// How the bar's background is drawn. `.glass` is the macOS 26 Liquid Glass
/// material; below 26 it silently renders as `.translucent`.
enum BarStyle: String, Codable, CaseIterable, Identifiable {
    case glass
    case translucent
    case solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .glass: return "Liquid Glass"
        case .translucent: return "Translucent"
        case .solid: return "Solid"
        }
    }

    var isAvailable: Bool {
        guard case .glass = self else { return true }
        if #available(macOS 26, *) { return true }
        return false
    }
}

/// One taskbar button per window, or one per application.
enum GroupingMode: String, Codable, CaseIterable, Identifiable {
    case perWindow
    case byApp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .perWindow: return "One button per window"
        case .byApp: return "Group by app"
        }
    }
}

struct AppearanceSettings: Codable, Equatable {
    var style: BarStyle
    var tintHex: String?
    var tintOpacity: Double
    var backgroundOpacity: Double
    var barThickness: Double
    var cornerRadius: Double
    var showsSeparator: Bool

    static let `default` = AppearanceSettings(
        style: .glass,
        tintHex: nil,
        tintOpacity: 0,
        backgroundOpacity: 1,
        barThickness: 48,
        cornerRadius: 0,
        showsSeparator: true
    )

    // Decoded field by field so that adding a property in a future release
    // leaves the user's existing config.json intact instead of resetting it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        style = try c.decodeIfPresent(BarStyle.self, forKey: .style) ?? d.style
        tintHex = try c.decodeIfPresent(String.self, forKey: .tintHex)
        tintOpacity = try c.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? d.tintOpacity
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? d.backgroundOpacity
        barThickness = try c.decodeIfPresent(Double.self, forKey: .barThickness) ?? d.barThickness
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        showsSeparator = try c.decodeIfPresent(Bool.self, forKey: .showsSeparator) ?? d.showsSeparator
    }

    init(style: BarStyle, tintHex: String?, tintOpacity: Double, backgroundOpacity: Double,
         barThickness: Double, cornerRadius: Double, showsSeparator: Bool) {
        self.style = style
        self.tintHex = tintHex
        self.tintOpacity = tintOpacity
        self.backgroundOpacity = backgroundOpacity
        self.barThickness = barThickness
        self.cornerRadius = cornerRadius
        self.showsSeparator = showsSeparator
    }
}

struct TaskbarSettings: Codable, Equatable {
    var edge: BarEdge
    var grouping: GroupingMode
    var showsWindowTitles: Bool
    var iconSize: Double
    var maxButtonWidth: Double
    var autoHide: Bool
    var showsOnAllDisplays: Bool
    /// Keyed by display UUID rather than CGDirectDisplayID — display IDs are
    /// reassigned across reboots and cable swaps, UUIDs are stable.
    var disabledDisplayUUIDs: [String]

    static let `default` = TaskbarSettings(
        edge: .bottom,
        grouping: .perWindow,
        showsWindowTitles: true,
        iconSize: 24,
        maxButtonWidth: 180,
        autoHide: false,
        showsOnAllDisplays: true,
        disabledDisplayUUIDs: []
    )

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        edge = try c.decodeIfPresent(BarEdge.self, forKey: .edge) ?? d.edge
        grouping = try c.decodeIfPresent(GroupingMode.self, forKey: .grouping) ?? d.grouping
        showsWindowTitles = try c.decodeIfPresent(Bool.self, forKey: .showsWindowTitles) ?? d.showsWindowTitles
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? d.iconSize
        maxButtonWidth = try c.decodeIfPresent(Double.self, forKey: .maxButtonWidth) ?? d.maxButtonWidth
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? d.autoHide
        showsOnAllDisplays = try c.decodeIfPresent(Bool.self, forKey: .showsOnAllDisplays) ?? d.showsOnAllDisplays
        disabledDisplayUUIDs = try c.decodeIfPresent([String].self, forKey: .disabledDisplayUUIDs) ?? d.disabledDisplayUUIDs
    }

    init(edge: BarEdge, grouping: GroupingMode, showsWindowTitles: Bool, iconSize: Double,
         maxButtonWidth: Double, autoHide: Bool, showsOnAllDisplays: Bool, disabledDisplayUUIDs: [String]) {
        self.edge = edge
        self.grouping = grouping
        self.showsWindowTitles = showsWindowTitles
        self.iconSize = iconSize
        self.maxButtonWidth = maxButtonWidth
        self.autoHide = autoHide
        self.showsOnAllDisplays = showsOnAllDisplays
        self.disabledDisplayUUIDs = disabledDisplayUUIDs
    }
}

struct GeneralSettings: Codable, Equatable {
    var checksForUpdatesAutomatically: Bool
    /// Hide the macOS Dock while Duckows is running; restored on quit.
    var hidesSystemDock: Bool

    /// Launch-at-login is deliberately absent. `SMAppService` is the single
    /// source of truth; mirroring it here would let this file drift from
    /// reality the moment the user flips the switch in System Settings.
    static let `default` = GeneralSettings(
        checksForUpdatesAutomatically: true,
        hidesSystemDock: true
    )

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        checksForUpdatesAutomatically = try c.decodeIfPresent(Bool.self, forKey: .checksForUpdatesAutomatically)
            ?? d.checksForUpdatesAutomatically
        hidesSystemDock = try c.decodeIfPresent(Bool.self, forKey: .hidesSystemDock) ?? d.hidesSystemDock
    }

    init(checksForUpdatesAutomatically: Bool, hidesSystemDock: Bool) {
        self.checksForUpdatesAutomatically = checksForUpdatesAutomatically
        self.hidesSystemDock = hidesSystemDock
    }
}

/// The Dock setting Duckows overwrote, so it can be put back exactly.
///
/// `isDirty` stays true from the first mutation until a clean restore finishes.
/// Finding it still set at launch means the previous run died without
/// restoring, and the recorded value is the one to trust — never the Dock's
/// current state, which is whatever Duckows left behind.
struct DockRestoreState: Codable, Equatable {
    var autoHide: Bool
    var isDirty: Bool
}

struct AppSettings: Codable, Equatable {
    var general: GeneralSettings
    var appearance: AppearanceSettings
    var taskbar: TaskbarSettings
    var dockRestore: DockRestoreState?

    static let `default` = AppSettings(
        general: .default,
        appearance: .default,
        taskbar: .default,
        dockRestore: nil
    )

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        general = try c.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? d.general
        appearance = try c.decodeIfPresent(AppearanceSettings.self, forKey: .appearance) ?? d.appearance
        taskbar = try c.decodeIfPresent(TaskbarSettings.self, forKey: .taskbar) ?? d.taskbar
        dockRestore = try c.decodeIfPresent(DockRestoreState.self, forKey: .dockRestore)
    }

    init(general: GeneralSettings, appearance: AppearanceSettings,
         taskbar: TaskbarSettings, dockRestore: DockRestoreState?) {
        self.general = general
        self.appearance = appearance
        self.taskbar = taskbar
        self.dockRestore = dockRestore
    }
}
