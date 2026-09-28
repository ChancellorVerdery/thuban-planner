import Foundation

/// Persistence for `PlannerData`: ONE JSON document (`planner.json`) written atomically on every change, plus rolling
/// daily backups and labelled snapshots (before an import / restore).
///
/// Why a single JSON document rather than SQLite / Core Data / SwiftData:
/// - Size: a degree is a few dozen classes and terms — a few KB, so rewriting the whole file per change costs well
///   under a millisecond and never loses an edit (no debouncing needed).
/// - Safety: `Data.write(.atomic)` writes a temp file and renames it, so a crash leaves either the old or the new
///   document, never a torn one. Backups are plain file copies.
/// - Simplicity: `PlannerData` is a value type; every rule (scheduler, mutations, import) is a pure function over it
///   and is unit-tested without a database. The format mirrors Atlas's blob, is human-readable and diffable.
public final class PlannerStore: @unchecked Sendable {
    /// Daily backups kept (`backups/planner-daily-yyyy-MM-dd.json`).
    public static let dailyBackupsKept = 14
    /// Labelled snapshots kept (`backups/planner-<label>-<timestamp>.json`).
    public static let snapshotsKept = 20

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("planner.json") }
    public var backupsDirectory: URL { directory.appendingPathComponent("backups", isDirectory: true) }

    private let fileManager = FileManager.default

    /// `directory` defaults to `AppPaths.home` (honours `THUBAN_GYM_HOME`).
    public init(directory: URL = AppPaths.home) {
        self.directory = directory
    }

    // MARK: Load / save

    /// The stored document, or `PlannerData.empty` when there is none yet. Throws `ThubanError.store` when the file
    /// exists but cannot be decoded (the caller should offer to restore a backup rather than overwrite it).
    public func load() throws -> PlannerData {
        try JSONFile.read(PlannerData.self, from: fileURL) ?? .empty
    }

    public var exists: Bool { fileManager.fileExists(atPath: fileURL.path) }

    /// Writes atomically. Before the first write of a calendar day, the previous file is copied to a daily backup.
    public func save(_ data: PlannerData, now: Date = Date()) throws {
        try ensureDirectories()
        try rollDailyBackup(day: PlannerStore.dayStamp(now))
        try JSONFile.write(data, to: fileURL, permissions: 0o600)
    }

    // MARK: Backups

    public struct Backup: Hashable, Sendable, Identifiable {
        public var url: URL
        public var created: Date
        public var size: Int
        /// "daily", "before-import", "before-restore" …
        public var label: String
        public var id: URL { url }
    }

    /// Copies the current document to `backups/planner-<label>-<yyyyMMdd-HHmmss>.json` and returns its URL (nil when
    /// there is no document yet).
    @discardableResult
    public func snapshot(label: String, now: Date = Date()) throws -> URL? {
        guard exists else { return nil }
        try ensureDirectories()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safe = label.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        var url = backupsDirectory.appendingPathComponent("planner-\(String(safe))-\(formatter.string(from: now)).json")
        var counter = 2
        while fileManager.fileExists(atPath: url.path) {
            url = backupsDirectory.appendingPathComponent("planner-\(String(safe))-\(formatter.string(from: now))-\(counter).json")
            counter += 1
        }
        do {
            try fileManager.copyItem(at: fileURL, to: url)
            try? fileManager.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        } catch {
            throw ThubanError.store("Backup failed: \(error.localizedDescription)")
        }
        prune(prefix: "planner-", excluding: "planner-daily-", keep: PlannerStore.snapshotsKept)
        return url
    }

    /// Every backup, newest first.
    public func backups() -> [Backup] {
        guard let urls = try? fileManager.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return [] }
        return urls.filter { $0.pathExtension == "json" }.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let name = url.deletingPathExtension().lastPathComponent
            let label: String
            if name.hasPrefix("planner-daily-") {
                label = "daily"
            } else {
                // planner-<label>-yyyyMMdd-HHmmss[-n]
                let parts = name.dropFirst("planner-".count).split(separator: "-")
                let words = parts.prefix { part in !(part.count == 8 && part.allSatisfy(\.isNumber)) }
                label = words.joined(separator: "-")
            }
            return Backup(url: url, created: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0, label: label)
        }
        .sorted { $0.created > $1.created }
    }

    /// Reads a backup (or any exported `planner.json`) without applying it.
    public func read(backup url: URL) throws -> PlannerData {
        guard let data = try JSONFile.read(PlannerData.self, from: url) else { throw ThubanError.store("\(url.lastPathComponent) does not exist.") }
        return data
    }

    // MARK: Internals

    /// "yyyy-MM-dd" in the local calendar (the daily backup's name).
    static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func ensureDirectories() throws {
        for url in [directory, backupsDirectory] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    private func rollDailyBackup(day: String) throws {
        guard exists else { return }
        let url = backupsDirectory.appendingPathComponent("planner-daily-\(day).json")
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.copyItem(at: fileURL, to: url)
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        prune(prefix: "planner-daily-", excluding: nil, keep: PlannerStore.dailyBackupsKept)
    }

    /// Keeps the newest `keep` files named `prefix…` (minus those named `excluding…`), by modification date.
    private func prune(prefix: String, excluding: String?, keep: Int) {
        guard let urls = try? fileManager.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let matching = urls.filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix) else { return false }
            if let excluding, name.hasPrefix(excluding) { return false }
            return true
        }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let newestFirst = matching.sorted { (modified($0), $0.lastPathComponent) > (modified($1), $1.lastPathComponent) }
        for url in newestFirst.dropFirst(keep) {
            try? fileManager.removeItem(at: url)
        }
    }
}
