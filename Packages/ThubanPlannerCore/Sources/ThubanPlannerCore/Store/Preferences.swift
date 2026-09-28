import Foundation

public enum TextSize: String, Codable, CaseIterable, Sendable {
    case compact, regular, large, extraLarge
    public var label: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }
    /// Multiplier applied to body sizes.
    public var scale: Double {
        switch self {
        case .compact: return 0.92
        case .regular: return 1
        case .large: return 1.12
        case .extraLarge: return 1.25
        }
    }
}

/// App preferences (`preferences.json`): appearance and where the Atlas import reads from. Kept apart from the
/// domain document so an import (which replaces `planner.json`) never touches them. Tolerant decoding.
public struct Preferences: Codable, Equatable, Sendable {
    public static let defaultAtlasHost = "beelink"
    public static let defaultAtlasEmail = "alex.morgan@example.com"

    public var theme: ThemeSelection = .default
    public var textSize: TextSize = .regular
    public var reduceMotion: Bool = false
    /// ssh host alias for the Atlas import (`~/.ssh/config` name or `user@host`).
    public var atlasHost: String = Preferences.defaultAtlasHost
    /// The Atlas account (auth.users.email) whose course-planner rows are imported.
    public var atlasEmail: String = Preferences.defaultAtlasEmail
    /// `AppSection.rawValue` of the last section shown.
    public var lastSection: String?
    /// The first-run "Import from Atlas?" offer was shown (or dismissed) once.
    public var importOffered: Bool = false

    public init() {}

    enum CodingKeys: String, CodingKey { case theme, textSize, reduceMotion, atlasHost, atlasEmail, lastSection, importOffered }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = (try? c.decodeIfPresent(ThemeSelection.self, forKey: .theme)) ?? .default
        textSize = (try? c.decodeIfPresent(TextSize.self, forKey: .textSize)) ?? .regular
        reduceMotion = (try? c.decodeIfPresent(Bool.self, forKey: .reduceMotion)) ?? false
        atlasHost = (try? c.decodeIfPresent(String.self, forKey: .atlasHost)) ?? Preferences.defaultAtlasHost
        atlasEmail = (try? c.decodeIfPresent(String.self, forKey: .atlasEmail)) ?? Preferences.defaultAtlasEmail
        lastSection = try? c.decodeIfPresent(String.self, forKey: .lastSection)
        importOffered = (try? c.decodeIfPresent(Bool.self, forKey: .importOffered)) ?? false
    }

    public static func load() -> Preferences {
        (try? JSONFile.read(Preferences.self, from: AppPaths.preferencesFile)) ?? Preferences()
    }

    public static func save(_ preferences: Preferences) throws {
        try AppPaths.ensureDirectories()
        try JSONFile.write(preferences, to: AppPaths.preferencesFile)
    }
}
