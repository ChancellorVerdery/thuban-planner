import Foundation

/// Where the app keeps its files. `THUBAN_PLANNER_HOME` overrides the root (tests and the smoke run use a temp dir).
public enum AppPaths {
    public static let homeVariable = "THUBAN_PLANNER_HOME"

    /// `~/Library/Application Support/Thuban Planner` unless overridden.
    public static var home: URL {
        if let raw = ProcessInfo.processInfo.environment[homeVariable]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Thuban Planner", isDirectory: true)
    }

    /// The domain document (courses, terms, settings).
    public static var dataFile: URL { home.appendingPathComponent("planner.json") }
    /// App preferences (theme, Atlas host/email, last section) — never replaced by an import.
    public static var preferencesFile: URL { home.appendingPathComponent("preferences.json") }
    public static var backupsDirectory: URL { home.appendingPathComponent("backups", isDirectory: true) }

    public static func ensureDirectories() throws {
        for url in [home, backupsDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}
