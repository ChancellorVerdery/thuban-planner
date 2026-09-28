import AppKit
import Foundation
import ThubanPlannerCore

/// A fetched / loaded import waiting for the user's confirmation.
struct ImportPreview: Equatable {
    var summary: ImportSummary
    var data: PlannerData
    /// "atlas:beelink" or "file:<name>".
    var source: String
    /// The local plan is not empty, so applying replaces something (confirm; a backup is made first).
    var replacesExisting: Bool
    /// What is here now, for the "replaces …" line.
    var localCourses: Int
    var localTerms: Int

    static func == (a: ImportPreview, b: ImportPreview) -> Bool {
        a.summary == b.summary && a.data == b.data && a.source == b.source && a.replacesExisting == b.replacesExisting
            && a.localCourses == b.localCourses && a.localTerms == b.localTerms
    }
}

/// Settings → Import state machine: idle → fetching → preview → applying → done (or failed).
enum ImportPhase: Equatable {
    case idle
    /// ssh / file read in flight (cancellable with `cancelImport()`).
    case fetching
    /// Decoded and converted; nothing written yet. Show the counts and ask to apply.
    case preview(ImportPreview)
    case applying
    /// Applied. `backup` is the snapshot of what was replaced (nil when there was nothing).
    case done(ImportSummary, backup: URL?)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .fetching, .applying: return true
        default: return false
        }
    }
}

/// Atlas import (read-only on the Atlas side, preview before replacing) and local backups.
extension AppModel {
    /// Importer configured from Settings (host + email) and `commandRunner`.
    var atlasImporter: AtlasImporter {
        AtlasImporter(host: preferences.atlasHost, email: preferences.atlasEmail, runner: commandRunner)
    }

    /// Step 1 (Atlas): runs the read-only SQL over ssh, converts, and moves to `.preview`. Nothing is written.
    func fetchAtlasPreview() {
        startImport(source: "atlas:\(preferences.atlasHost)") { [atlasImporter] in
            try await atlasImporter.fetch()
        }
    }

    /// Step 1 (file): reads a saved Atlas JSON document (same shape the SQL returns) and moves to `.preview`.
    func loadImportFile(_ url: URL) {
        lastImportFile = url
        startImport(source: "file:\(url.lastPathComponent)") {
            try AtlasImporter.document(fromFile: url)
        }
    }

    /// Asks for a file with an open panel, then `loadImportFile`.
    func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an Atlas course-planner export (JSON)"
        if panel.runModal() == .OK, let url = panel.url { loadImportFile(url) }
    }

    /// Step 2: snapshots the current plan ("before-import"), then replaces it with the preview.
    func applyImport() {
        guard case .preview(let preview) = importPhase else { return }
        importPhase = .applying
        do {
            let backup = try store.snapshot(label: "before import")
            var incoming = preview.data
            incoming.importSource = preview.source
            replaceData(incoming)
            importPhase = .done(preview.summary, backup: backup)
        } catch {
            importPhase = .failed(error.localizedDescription)
        }
    }

    /// Cancels a running fetch, or dismisses a preview / result.
    func cancelImport() {
        importRun += 1
        importTask?.cancel()
        importTask = nil
        importPhase = .idle
    }

    /// The first-run offer ("Import your plan from Atlas?") was answered — never shown again.
    func dismissImportOffer() { preferences.importOffered = true }

    /// Show the first-run import offer: no plan file at launch, nothing entered yet, not answered before.
    var shouldOfferImport: Bool { isFirstRun && data.isEmpty && !preferences.importOffered }

    private func startImport(source: String, load: @escaping @Sendable () async throws -> AtlasDocument) {
        importTask?.cancel()
        importRun += 1
        let run = importRun
        lastImportSource = source
        importPhase = .fetching
        let calendar = self.calendar
        importTask = Task { @MainActor [weak self] in
            // A cancelled or superseded run never touches the phase of the run that replaced it.
            @MainActor func isCurrent() -> Bool { self?.importRun == run }
            do {
                let document = try await load()
                try Task.checkCancellation()
                let converted = try AtlasImporter.convert(document, source: source, now: Date(), calendar: calendar)
                guard let self, isCurrent() else { return }
                self.importPhase = .preview(ImportPreview(
                    summary: converted.summary, data: converted.data, source: source,
                    replacesExisting: !self.data.isEmpty,
                    localCourses: self.data.courses.count, localTerms: self.data.terms.count))
            } catch is CancellationError {
                if isCurrent() { self?.importPhase = .idle }
            } catch {
                if isCurrent() { self?.importPhase = .failed(error.localizedDescription) }
            }
        }
    }

    // MARK: Backups and data

    var dataFolder: URL { store.directory }

    /// Daily backups and labelled snapshots, newest first.
    func backups() -> [PlannerStore.Backup] { store.backups() }

    /// Replaces the plan with a backup (after snapshotting the current one as "before-restore").
    func restoreBackup(_ url: URL) throws {
        let restored = try store.read(backup: url)
        try store.snapshot(label: "before restore")
        replaceData(restored)
    }

    /// Writes the current plan to `url` (Settings → Data → Export).
    func exportData(to url: URL) throws {
        try JSONFile.write(data, to: url)
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }
}
