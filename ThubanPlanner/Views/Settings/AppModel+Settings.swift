import Foundation
import ThubanPlannerCore

/// Read-only queries the Settings panes need. OWNER: Engineer C. Every member is prefixed `settings…`.
extension AppModel {
    /// The route the plan WOULD have with `settings` (a copy of the plan; nothing is written). Used by the Planning
    /// pane's live preview while a cap is still being typed and for each strategy row.
    func settingsPreviewSchedule(_ settings: PlannerSettings) -> Schedule {
        // Automatic summers: preview on the same effective plan the route uses.
        var copy = summerAutomation?.effective ?? data
        copy.settings = settings
        copy.normalize()
        return Scheduler.scheduleDegree(copy, now: now, calendar: calendar)
    }

    /// When `planner.json` was last written (nil before the first save).
    var settingsLastSaved: Date? {
        (try? store.fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// The plan file's size in bytes (0 when there is none).
    var settingsFileSize: Int {
        (try? store.fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    /// True when Host and email both pass the importer's validation.
    var settingsImportConnectionIsValid: Bool {
        (try? AtlasImporter.validateHost(preferences.atlasHost)) != nil
            && (try? AtlasImporter.validateEmail(preferences.atlasEmail)) != nil
    }
}

/// Wording shared by the Settings panes.
enum SettingsFormat {
    /// "Spring 2028 · 3 more terms", "Nothing left to schedule", or "Can't finish — 2 classes can't be placed".
    static func finish(_ schedule: Schedule, remaining: Int) -> String {
        if remaining == 0 { return "Nothing left to schedule" }
        if !schedule.unplaceable.isEmpty {
            let n = schedule.unplaceable.count
            return "\(n) class\(n == 1 ? "" : "es") can't be placed"
        }
        guard let grad = schedule.gradTermLabel, schedule.termsToFinish > 0 else { return "Nothing left to schedule" }
        let n = schedule.termsToFinish
        return "\(grad) · \(n) term\(n == 1 ? "" : "s")"
    }

    /// "1 more term" / "3 more terms".
    static func terms(_ n: Int) -> String { "\(n) more term\(n == 1 ? "" : "s")" }

    /// "Tue Sep 29, 4:05 PM"
    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d, h:mm a"
        return formatter.string(from: date)
    }

    /// "Sep 29, 2026"
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    /// Where an import came from, in words: "Atlas on beelink" / "the file plan.json".
    static func source(_ source: String) -> String {
        if source.hasPrefix("file:") { return "the file \(source.dropFirst(5))" }
        if source.hasPrefix("atlas:") { return "Atlas on \(source.dropFirst(6))" }
        return source
    }

    /// "a backup label" → "Before import" etc.
    static func backupLabel(_ label: String) -> String {
        switch label {
        case "daily": return "Daily"
        case "before-import": return "Before import"
        case "before-restore": return "Before restore"
        default: return label.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
}
