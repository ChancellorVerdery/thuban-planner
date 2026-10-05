import AppKit
import Foundation
import Observation
import ThubanPlannerCore
import UniformTypeIdentifiers
import os

/// Technical electives and degree-document import (`app.degreeTools`). Owns the bundled catalog dataset, the Banner
/// offerings cache (`offerings-cache.json`, refreshed weekly from the public class search; the bundled snapshot until
/// then and in the offline smoke run), and the state of the two sheets the shell hosts. Every write goes through
/// `app.mutate`, only after the user confirms.
@MainActor
@Observable
final class DegreeToolsModel {
    static let logger = Logger(subsystem: "org.thuban.planner", category: "degree-tools")

    enum Sheet: String, Identifiable {
        case electives, degreeImport
        var id: String { rawValue }
    }

    enum ElectivesStage: Equatable {
        case list
        /// The "Add PHYS 4242 and 2 prerequisites?" confirmation.
        case confirmAdd(String)
        /// "Remove PHYS 4242?" with the prerequisites added only for it.
        case confirmRemove(String)
    }

    enum ElectiveFilter: String, Hashable, CaseIterable {
        case all, megr, other
        var label: String {
            switch self {
            case .all: return "All"
            case .megr: return "MEGR"
            case .other: return "Other"
            }
        }
    }

    enum OfferingsPhase: Equatable {
        case idle
        case fetching(done: Int, total: Int)
        case failed(String)
    }

    /// Where the classes just added landed on the route.
    struct Placement: Equatable, Identifiable {
        var id: String
        var code: String
        var title: String
        var term: String?
        var isElective: Bool
    }

    struct AddResult: Equatable {
        var target: String
        var placements: [Placement]
    }

    struct ImportDraft: Equatable {
        var fileName: String
        var format: DegreeDocumentText.Format
        var plan: DegreeImportPlan
        var include: Set<String>
        var picks: [String: Set<String>]

        var pickedCount: Int { picks.values.reduce(0) { $0 + $1.count } }
        var addCount: Int { include.count + pickedCount }
        var addCredits: Double {
            let base = plan.toAdd.filter { include.contains($0.code) }.reduce(0) { $0 + $1.credits }
            let chosen = plan.choices.flatMap { c in c.available.filter { picks[c.id]?.contains($0.code) == true } }.reduce(0) { $0 + $1.credits }
            return base + chosen
        }
    }

    struct ImportResult: Equatable {
        var program: String
        var fileName: String
        var placements: [Placement]
        var backup: URL?
    }

    enum ImportPhase: Equatable {
        case choose
        case loading(String)
        case preview(ImportDraft)
        case done(ImportResult)
        case failed(String)
    }

    // MARK: State

    @ObservationIgnored weak var app: AppModel?
    let dataset: CatalogDataset?
    private(set) var offerings: CourseOfferings
    var offeringsPhase: OfferingsPhase = .idle
    /// The sheet the shell shows.
    var sheet: Sheet?

    // Electives sheet
    var stage: ElectivesStage = .list
    var filter: ElectiveFilter = .all
    var search = ""
    var showNotOffered = false
    /// OR-group key → the option the user picked in the confirmation.
    var choices: [String: String] = [:]
    var lastAdd: AddResult?
    /// Course ids ticked for removal with an elective.
    var removalSelection: Set<String> = []

    // Degree import sheet
    var importPhase: ImportPhase = .choose

    @ObservationIgnored let offline: Bool
    @ObservationIgnored let offeringsStore: OfferingsStore
    @ObservationIgnored var client = BannerClient()
    @ObservationIgnored private var offeringsTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var statusCache: (data: PlannerData, offerings: CourseOfferings, now: String, value: [TechElectives.Status])?

    init(directory: URL, offline: Bool) {
        self.offline = offline
        offeringsStore = OfferingsStore(directory: directory)
        dataset = CatalogDataset.bsme2025
        let cached = offline ? CourseOfferings.empty : offeringsStore.load()
        offerings = cached.byTerm.isEmpty ? (CourseOfferings.bundledSnapshot ?? cached) : cached
    }

    // MARK: Sheets

    func openElectives() {
        stage = .list
        lastAdd = nil
        sheet = .electives
        refreshOfferingsIfNeeded()
    }

    func openImport() {
        if case .loading = importPhase {} else { importPhase = .choose }
        sheet = .degreeImport
    }

    func closeSheet() {
        sheet = nil
        stage = .list
        choices = [:]
        importTask?.cancel()
        if case .loading = importPhase { importPhase = .choose }
    }

    // MARK: Electives — reads

    var window: CourseOfferings.Window {
        offerings.window(now: app?.now ?? Date())
    }

    /// Every elective's status against the current plan (cached until the plan or offerings change).
    var statuses: [TechElectives.Status] {
        guard let app, let dataset else { return [] }
        let nowKey = TermKey.current(now: app.now, calendar: app.calendar)
        if let cache = statusCache, cache.now == nowKey, cache.offerings == offerings, cache.data == app.data { return cache.value }
        let value = TechElectives.statuses(dataset: dataset, data: app.data, offerings: offerings, window: offerings.window(now: app.now, calendar: app.calendar))
        statusCache = (app.data, offerings, nowKey, value)
        return value
    }

    var progress: TechElectives.Progress? {
        guard let app, let dataset else { return nil }
        return TechElectives.progress(dataset: dataset, data: app.data)
    }

    /// The list the sheet shows: filter, search, offered-only unless the toggle is on; chosen ones first.
    var visibleStatuses: [TechElectives.Status] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return statuses.filter { s in
            switch filter {
            case .all: break
            case .megr: guard s.isMEGR else { return false }
            case .other: guard !s.isMEGR else { return false }
            }
            if !query.isEmpty, !s.code.lowercased().contains(query), !s.title.lowercased().contains(query),
               !CourseCode.key(s.code).lowercased().contains(query.filter { !$0.isWhitespace }) { return false }
            return showNotOffered || s.isOffered || s.planState != .notInPlan
        }
        // Chosen / in-plan electives first, then the catalog's order.
        .enumerated().sorted { a, b in
            let pa = a.element.planState == .notInPlan ? 1 : 0, pb = b.element.planState == .notInPlan ? 1 : 0
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map(\.element)
    }

    var hiddenNotOfferedCount: Int {
        statuses.filter { !$0.isOffered && $0.planState == .notInPlan }.count
    }

    func chainPlan(for code: String) -> ChainPlan? {
        guard let app, let dataset else { return nil }
        let offerings = self.offerings
        let window = offerings.window(now: app.now, calendar: app.calendar)
        return RequirementChainResolver(dataset: dataset, data: app.data) { offerings.summary(for: $0, window: window) }
            .resolve([code], choices: choices)
    }

    func offering(_ code: String) -> CourseOfferings.Summary {
        offerings.summary(for: code, window: window)
    }

    /// "Spring 2026, Spring 2025 · upcoming Spring 2027" / "Fall 2026, Spring 2026 + 2 more · upcoming Spring 2027" /
    /// "No sections in the last two years".
    func offeringText(_ summary: CourseOfferings.Summary) -> String {
        guard summary.known else { return "Offerings not checked yet" }
        var parts: [String] = []
        if !summary.past.isEmpty {
            parts.append(summary.past.prefix(2).map(TermKey.label).joined(separator: ", ") + (summary.past.count > 2 ? " + \(summary.past.count - 2) more" : ""))
        }
        if !summary.upcoming.isEmpty { parts.append("upcoming " + summary.upcoming.map(TermKey.label).joined(separator: ", ")) }
        return parts.isEmpty ? "No sections in the last two years" : parts.joined(separator: " · ")
    }

    var offeringsCaption: String {
        switch offeringsPhase {
        case .fetching(let done, let total): return total > 0 ? "Checking Banner’s class search… \(done) / \(total)" : "Checking Banner’s class search…"
        case .failed(let message): return "Couldn’t refresh offerings: \(message)"
        case .idle:
            let w = window
            let span = w.past.isEmpty ? "" : "\(w.past.last.map { TermKey.label($0.termKey ?? "") } ?? "") – \(w.upcoming.last.map { TermKey.label($0.termKey ?? "") } ?? w.past.first.map { TermKey.label($0.termKey ?? "") } ?? "")"
            guard let date = offerings.lastFetched(window: w) else { return "Offerings not checked yet" }
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return "Sections \(span) · Banner class search, checked \(f.string(from: date))"
        }
    }

    // MARK: Electives — writes

    /// Choosing an elective: everything it needs is in the plan → added right away; otherwise the confirmation.
    func choose(_ code: String) {
        guard let plan = chainPlan(for: code) else { return }
        if plan.prerequisiteAdditions.isEmpty && plan.choices.isEmpty && plan.warnings.isEmpty {
            apply(plan, target: code)
        } else {
            lastAdd = nil
            stage = .confirmAdd(code)
        }
    }

    func setChoice(_ key: String, _ option: String) {
        choices[key] = option
    }

    func confirmAdd() {
        guard case .confirmAdd(let code) = stage, let plan = chainPlan(for: code) else { return }
        apply(plan, target: code)
        stage = .list
        choices = [:]
    }

    func cancelStage() {
        stage = .list
        choices = [:]
        removalSelection = []
    }

    private func apply(_ plan: ChainPlan, target: String) {
        guard let app else { return }
        let ids = app.mutate { data in TechElectives.apply(plan, to: &data) }
        lastAdd = AddResult(target: CourseCode.normalize(target), placements: placements(ids))
    }

    private func placements(_ ids: [String]) -> [Placement] {
        guard let app else { return [] }
        return ids.compactMap { id in
            guard let c = app.course(id) else { return nil }
            return Placement(id: id, code: c.code, title: c.title, term: app.routeTerm(of: id)?.label,
                             isElective: c.tags?.contains(TechElectives.electiveTag) == true)
        }
    }

    func beginRemove(_ code: String) {
        guard let app else { return }
        let removal = TechElectives.removal(of: code, data: app.data)
        guard removal.elective != nil else { return }
        removalSelection = Set(removal.prerequisites.map(\.id))
        lastAdd = nil
        stage = .confirmRemove(code)
    }

    func removal(of code: String) -> (elective: Course?, prerequisites: [Course]) {
        guard let app else { return (nil, []) }
        return TechElectives.removal(of: code, data: app.data)
    }

    func confirmRemove() {
        guard case .confirmRemove(let code) = stage, let app else { return }
        let removal = TechElectives.removal(of: code, data: app.data)
        guard let elective = removal.elective else { stage = .list; return }
        let ids = Set([elective.id]).union(removal.prerequisites.map(\.id).filter(removalSelection.contains))
        app.mutate { data in data.courses.removeAll { ids.contains($0.id) } }
        removalSelection = []
        stage = .list
    }

    // MARK: Offerings

    /// Fetches what the window is missing (finished terms once, the current / upcoming ones weekly). Never in a
    /// smoke run.
    func refreshOfferingsIfNeeded(force: Bool = false) {
        guard !offline, let dataset, offeringsTask == nil else { return }
        let now = Date()
        var start = offeringsStore.load()
        if start.byTerm.isEmpty, let snapshot = CourseOfferings.bundledSnapshot { start = snapshot }
        if force {
            for code in start.byTerm.keys {
                guard let key = BannerTermCode.termKey(code), TermKey.rank(key) >= TermKey.rank(TermKey.current(now: now)) else { continue }
                start.byTerm[code] = nil
            }
            start.termsFetchedAt = nil
        }
        let subjects = dataset.electiveSubjects
        guard start.termsAreStale(now: now) || !OfferingsFetcher.pending(start, subjects: subjects, now: now).isEmpty else {
            offerings = start
            return
        }
        offeringsPhase = .fetching(done: 0, total: 0)
        let fetcher = OfferingsFetcher(client: client)
        let store = offeringsStore
        offeringsTask = Task { [weak self] in
            do {
                let result = try await fetcher.refresh(start, subjects: subjects, now: now, progress: { done, total in
                    await MainActor.run { self?.offeringsPhase = .fetching(done: done, total: total) }
                }, save: { snapshot in
                    try? store.save(snapshot)
                    await MainActor.run { self?.offerings = snapshot }
                })
                try? store.save(result)
                self?.offerings = result
                self?.offeringsPhase = .idle
            } catch is CancellationError {
                self?.offeringsPhase = .idle
            } catch {
                Self.logger.error("offerings refresh failed: \(error.localizedDescription, privacy: .public)")
                self?.offeringsPhase = .failed(error.localizedDescription)
            }
            self?.offeringsTask = nil
        }
    }

    // MARK: Degree import

    static let importTypes: [UTType] = [.pdf, .html, .plainText, .text, UTType(filenameExtension: "mhtml"), UTType(filenameExtension: "mht"),
                                        UTType(filenameExtension: "md"), UTType(filenameExtension: "docx")].compactMap { $0 }

    func chooseDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.importTypes
        panel.allowsMultipleSelection = false
        panel.message = "Choose a UNC Charlotte degree document — a catalog program page (PDF, HTML or MHTML), a DegreeWorks audit, or a checksheet"
        if panel.runModal() == .OK, let url = panel.url { loadDocument(url) }
    }

    func loadDocument(_ url: URL) {
        importTask?.cancel()
        importPhase = .loading(url.lastPathComponent)
        sheet = .degreeImport
        importTask = Task { [weak self] in
            let parsed: Result<(DegreeDocumentText.Extracted, ParsedDegreeDocument), Error> = await Task.detached {
                do {
                    let ex = try DegreeDocumentText.extract(contentsOf: url)
                    return .success((ex, DegreeDocumentParser.parse(ex.text, heading: ex.heading)))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch parsed {
            case .success(let (ex, doc)):
                self.preview(doc, fileName: url.lastPathComponent, format: ex.format)
            case .failure(let error):
                self.importPhase = .failed(error.localizedDescription)
            }
        }
    }

    /// Builds the preview for a parsed document (also used by the smoke scenes).
    func preview(_ document: ParsedDegreeDocument, fileName: String, format: DegreeDocumentText.Format) {
        guard let app else { return }
        let plan = DegreeImportMerge.plan(document, documentName: fileName, data: app.data, dataset: dataset)
        importPhase = .preview(ImportDraft(fileName: fileName, format: format, plan: plan, include: Set(plan.toAdd.map(\.code)), picks: [:]))
    }

    func toggleInclude(_ code: String) {
        guard case .preview(var draft) = importPhase else { return }
        if draft.include.contains(code) { draft.include.remove(code) } else { draft.include.insert(code) }
        importPhase = .preview(draft)
    }

    func togglePick(_ choiceId: String, _ code: String) {
        guard case .preview(var draft) = importPhase else { return }
        var set = draft.picks[choiceId] ?? []
        if set.contains(code) { set.remove(code) } else { set.insert(code) }
        draft.picks[choiceId] = set.isEmpty ? nil : set
        importPhase = .preview(draft)
    }

    /// Snapshot first ("before degree import"), then ONE write adding the ticked classes and picked options.
    func applyImport() {
        guard case .preview(let draft) = importPhase, let app else { return }
        var backup: URL?
        if !SmokeHarness.isEnabled {
            do { backup = try app.store.snapshot(label: "before degree import") } catch {
                importPhase = .failed("A backup couldn’t be made, so nothing was changed: \(error.localizedDescription)")
                return
            }
        }
        let picks = draft.picks.mapValues { Array($0) }
        let ids = app.mutate { data in DegreeImportMerge.apply(draft.plan, include: draft.include, picks: picks, to: &data) }
        importPhase = .done(ImportResult(program: draft.plan.programName ?? draft.fileName, fileName: draft.fileName,
                                         placements: placements(ids), backup: backup))
    }

    func resetImport() {
        importTask?.cancel()
        importPhase = .choose
    }
}
