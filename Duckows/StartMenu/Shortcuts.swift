import AppKit

/// The folders the old Start menu kept in its right-hand column.
enum PlaceShortcut: String, CaseIterable, Identifiable {
    case home
    case documents
    case downloads
    case applications

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .home:         return NSUserName()
        case .documents:    return "Documents"
        case .downloads:    return "Downloads"
        case .applications: return "Applications"
        }
    }

    var symbolName: String {
        switch self {
        case .home:         return "house"
        case .documents:    return "doc"
        case .downloads:    return "arrow.down.circle"
        case .applications: return "square.stack"
        }
    }

    private var url: URL {
        switch self {
        case .home:         return FileManager.default.homeDirectoryForCurrentUser
        case .documents:    return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents")
        case .downloads:    return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
        case .applications: return URL(fileURLWithPath: "/Applications")
        }
    }

    func open() {
        NSWorkspace.shared.open(url)
    }
}

/// System Settings panes worth one click.
///
/// The identifiers are the modern extension bundle ids, read from System
/// Settings' own sidebar configuration on macOS 26. Apple renames these every
/// couple of releases, which is exactly why they all live in one file.
enum SystemSettingsPane: String, CaseIterable, Identifiable {
    case settings
    case displays
    case sound
    case network
    case bluetooth
    case accessibility

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .settings:      return "System Settings"
        case .displays:      return "Displays"
        case .sound:         return "Sound"
        case .network:       return "Network"
        case .bluetooth:     return "Bluetooth"
        case .accessibility: return "Accessibility"
        }
    }

    var symbolName: String {
        switch self {
        case .settings:      return "gearshape"
        case .displays:      return "display"
        case .sound:         return "speaker.wave.2"
        case .network:       return "network"
        case .bluetooth:     return "wave.3.right"
        case .accessibility: return "figure.arms.open"
        }
    }

    private var paneIdentifier: String? {
        switch self {
        case .settings:      return nil
        case .displays:      return "com.apple.Displays-Settings.extension"
        case .sound:         return "com.apple.Sound-Settings.extension"
        case .network:       return "com.apple.Network-Settings.extension"
        case .bluetooth:     return "com.apple.BluetoothSettings"
        case .accessibility:
            return "com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        }
    }

    static let startMenuItems: [SystemSettingsPane] = [.settings, .displays, .sound, .bluetooth, .network]

    func open() {
        guard let paneIdentifier else {
            // No anchor: just open System Settings itself.
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:\(paneIdentifier)") else { return }
        NSWorkspace.shared.open(url)
    }
}
