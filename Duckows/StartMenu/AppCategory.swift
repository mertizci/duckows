import Foundation

/// The `LSApplicationCategoryType` values Apple defines, plus a fallback.
///
/// Two realities shape this: roughly a quarter of installed apps declare no
/// category at all, and some declare something malformed, so the initialiser
/// never fails — it guesses instead.
enum AppCategory: String, Codable, CaseIterable, Identifiable {
    case developerTools      = "public.app-category.developer-tools"
    case productivity        = "public.app-category.productivity"
    case utilities           = "public.app-category.utilities"
    case graphicsDesign      = "public.app-category.graphics-design"
    case photography         = "public.app-category.photography"
    case video               = "public.app-category.video"
    case music               = "public.app-category.music"
    case entertainment       = "public.app-category.entertainment"
    case games               = "public.app-category.games"
    case socialNetworking    = "public.app-category.social-networking"
    case business            = "public.app-category.business"
    case finance             = "public.app-category.finance"
    case education           = "public.app-category.education"
    case reference           = "public.app-category.reference"
    case books               = "public.app-category.books"
    case news                = "public.app-category.news"
    case lifestyle           = "public.app-category.lifestyle"
    case healthcareFitness   = "public.app-category.healthcare-fitness"
    case medical             = "public.app-category.medical"
    case sports              = "public.app-category.sports"
    case travel              = "public.app-category.travel"
    case weather             = "public.app-category.weather"
    case other               = "com.duckows.app-category.other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .developerTools:    return "Developer"
        case .productivity:      return "Productivity"
        case .utilities:         return "Utilities"
        case .graphicsDesign:    return "Graphics & Design"
        case .photography:       return "Photography"
        case .video:             return "Video"
        case .music:             return "Music"
        case .entertainment:     return "Entertainment"
        case .games:             return "Games"
        case .socialNetworking:  return "Social"
        case .business:          return "Business"
        case .finance:           return "Finance"
        case .education:         return "Education"
        case .reference:         return "Reference"
        case .books:             return "Books"
        case .news:              return "News"
        case .lifestyle:         return "Lifestyle"
        case .healthcareFitness: return "Health & Fitness"
        case .medical:           return "Medical"
        case .sports:            return "Sports"
        case .travel:            return "Travel"
        case .weather:           return "Weather"
        case .other:             return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .developerTools:    return "hammer"
        case .productivity:      return "checkmark.circle"
        case .utilities:         return "wrench.and.screwdriver"
        case .graphicsDesign:    return "paintbrush"
        case .photography:       return "camera"
        case .video:             return "film"
        case .music:             return "music.note"
        case .entertainment:     return "popcorn"
        case .games:             return "gamecontroller"
        case .socialNetworking:  return "bubble.left.and.bubble.right"
        case .business:          return "briefcase"
        case .finance:           return "dollarsign.circle"
        case .education:         return "graduationcap"
        case .reference:         return "book.closed"
        case .books:             return "books.vertical"
        case .news:              return "newspaper"
        case .lifestyle:         return "leaf"
        case .healthcareFitness: return "heart"
        case .medical:           return "cross.case"
        case .sports:            return "figure.run"
        case .travel:            return "airplane"
        case .weather:           return "cloud.sun"
        case .other:             return "square.grid.2x2"
        }
    }

    /// Most-used first, with Other pinned to the end.
    static let displayOrder: [AppCategory] = allCases

    /// Never fails: a missing or malformed value falls through to a guess.
    init(rawCategory: String?, bundleURL: URL, bundleIdentifier: String) {
        if let raw = rawCategory, !raw.isEmpty {
            if let exact = AppCategory(rawValue: raw) {
                self = exact
                return
            }
            // Apple defines nineteen separate game sub-categories. A launcher
            // does not want nineteen game sections.
            if raw.hasSuffix("-games") {
                self = .games
                return
            }
        }
        self = Self.inferred(bundleURL: bundleURL, bundleIdentifier: bundleIdentifier)
    }

    private static func inferred(bundleURL: URL, bundleIdentifier: String) -> AppCategory {
        if bundleURL.deletingLastPathComponent().lastPathComponent == "Utilities" { return .utilities }
        if bundleURL.path.hasPrefix("/System/Library/CoreServices") { return .utilities }

        for (prefix, category) in knownPrefixes where bundleIdentifier.hasPrefix(prefix) {
            return category
        }
        return .other
    }

    /// The handful of vendors that ship no category and would otherwise all
    /// pile into "Other".
    private static let knownPrefixes: [(String, AppCategory)] = [
        ("com.jetbrains.", .developerTools),
        ("com.google.android.studio", .developerTools),
        ("com.microsoft.VSCode", .developerTools),
        ("com.todesktop.", .developerTools),
        ("com.docker.", .developerTools),
        ("dev.warp.", .developerTools),
        ("com.orbstack.", .developerTools),
        ("com.postmanlabs.", .developerTools),
        ("com.apple.dt.", .developerTools),
        ("com.valvesoftware.steam", .games),
        ("com.tinyspeck.slackmacgap", .socialNetworking),
        ("net.whatsapp.", .socialNetworking),
        ("com.hnc.Discord", .socialNetworking),
        ("com.spotify.client", .music),
        ("com.openai.chat", .productivity),
        ("com.anthropic.claudefordesktop", .productivity),
        ("com.1password.", .utilities),
        ("io.tailscale.", .utilities)
    ]
}
