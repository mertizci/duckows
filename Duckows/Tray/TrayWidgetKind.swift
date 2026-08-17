import Foundation

/// The things that can sit at the right-hand end of the bar.
enum TrayWidgetKind: String, Codable, CaseIterable, Identifiable {
    case systemLoad
    case wifi
    case bluetooth
    case volume
    case battery
    case clock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemLoad: return "CPU & Memory"
        case .wifi:       return "Wi-Fi"
        case .bluetooth:  return "Bluetooth"
        case .volume:     return "Volume"
        case .battery:    return "Battery"
        case .clock:      return "Clock"
        }
    }

    var symbolName: String {
        switch self {
        case .systemLoad: return "chart.bar"
        case .wifi:       return "wifi"
        case .bluetooth:  return "wave.3.right"
        case .volume:     return "speaker.wave.2"
        case .battery:    return "battery.100"
        case .clock:      return "clock"
        }
    }

    /// Left to right, ending with the clock, the way the menu bar reads.
    static let defaultOrder: [TrayWidgetKind] = [
        .systemLoad, .wifi, .bluetooth, .volume, .battery, .clock
    ]

    /// What is on by default. Two are off:
    ///
    /// - the load monitor is the one widget that costs something to run
    ///   continuously, and most people do not want a graph in their taskbar;
    /// - Bluetooth is the only widget that costs a permission prompt — on
    ///   macOS 26 even the private power-state call goes through the
    ///   CoreBluetooth TCC gate — and a taskbar should not ask for anything on
    ///   first launch.
    var isEnabledByDefault: Bool {
        self != .systemLoad && self != .bluetooth
    }
}

struct TrayWidgetConfig: Codable, Equatable, Identifiable {
    var kind: TrayWidgetKind
    var isEnabled: Bool

    var id: String { kind.rawValue }
}

enum ClockFormat: String, Codable, CaseIterable, Identifiable {
    case system
    case twelveHour
    case twentyFourHour

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:         return "System"
        case .twelveHour:     return "12-hour"
        case .twentyFourHour: return "24-hour"
        }
    }
}

struct TraySettings: Codable, Equatable {
    var widgets: [TrayWidgetConfig]
    var clockFormat: ClockFormat
    var showsDate: Bool
    var showsSeconds: Bool
    /// Off by default: the Windows notification area shows the battery as an
    /// icon alone, and the exact figure is one click away in the popover.
    var showsBatteryPercentage: Bool
    /// Mirror other apps' menu bar extras into the bar.
    var mirrorsMenuBarItems: Bool
    /// Push the real ones off the menu bar while Duckows is running.
    var hidesMirroredItems: Bool

    static let `default` = TraySettings(
        widgets: TrayWidgetKind.defaultOrder.map {
            TrayWidgetConfig(kind: $0, isEnabled: $0.isEnabledByDefault)
        },
        clockFormat: .system,
        showsDate: true,
        showsSeconds: false,
        showsBatteryPercentage: false,
        mirrorsMenuBarItems: false,
        hidesMirroredItems: false
    )

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        let stored = try c.decodeIfPresent([TrayWidgetConfig].self, forKey: .widgets) ?? d.widgets
        // A widget added in a later release has to appear for people who
        // already have a stored order, rather than silently never showing up.
        let known = Set(stored.map(\.kind))
        widgets = stored + d.widgets.filter { !known.contains($0.kind) }
        clockFormat = try c.decodeIfPresent(ClockFormat.self, forKey: .clockFormat) ?? d.clockFormat
        showsDate = try c.decodeIfPresent(Bool.self, forKey: .showsDate) ?? d.showsDate
        showsSeconds = try c.decodeIfPresent(Bool.self, forKey: .showsSeconds) ?? d.showsSeconds
        showsBatteryPercentage = try c.decodeIfPresent(Bool.self, forKey: .showsBatteryPercentage)
            ?? d.showsBatteryPercentage
        mirrorsMenuBarItems = try c.decodeIfPresent(Bool.self, forKey: .mirrorsMenuBarItems)
            ?? d.mirrorsMenuBarItems
        hidesMirroredItems = try c.decodeIfPresent(Bool.self, forKey: .hidesMirroredItems)
            ?? d.hidesMirroredItems
    }

    init(widgets: [TrayWidgetConfig], clockFormat: ClockFormat, showsDate: Bool,
         showsSeconds: Bool, showsBatteryPercentage: Bool,
         mirrorsMenuBarItems: Bool, hidesMirroredItems: Bool) {
        self.widgets = widgets
        self.clockFormat = clockFormat
        self.showsDate = showsDate
        self.showsSeconds = showsSeconds
        self.showsBatteryPercentage = showsBatteryPercentage
        self.mirrorsMenuBarItems = mirrorsMenuBarItems
        self.hidesMirroredItems = hidesMirroredItems
    }
}
