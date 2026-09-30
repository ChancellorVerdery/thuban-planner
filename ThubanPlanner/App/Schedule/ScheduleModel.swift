import AppKit
import Foundation
import Observation
import ThubanPlannerCore
import os

/// A course row in the Schedule sidebar: where it came from, its (effective) pin, and what Banner said about it.
struct ScheduleCourseRow: Identifiable, Hashable {
    enum Origin: Hashable { case route, added }

    /// Canonical "MEGR 2144".
    var code: String
    var title: String
    var credits: Double?
    var origin: Origin
    /// The user's pin for this course.
    var pinnedCRN: String?
    /// nil = not fetched yet.
    var sections: [BannerSection]?
    var linkedSets: [String: [[BannerSection]]]
    var fetchedAt: Date?
    var isFetching: Bool
    var error: String?

    var id: String { code }

    var openCount: Int { sections?.filter(\.hasOpenSeat).count ?? 0 }
}

/// The class detail sheet's subject: one section of one course in the current timetable.
struct ScheduleClassDetailItem: Identifiable, Hashable {
    var section: BannerSection
    /// Canonical course code (the row it belongs to; colour).
    var course: String

    var id: String { section.crn }
}

enum SchedulePhase: Equatable {
    case idle, loading
    case failed(String)
}

/// The Schedule tab's state: the Banner term, the courses (Thuban's route for that term plus any added by code),
/// their sections (fetched one course at a time, cached), the user's exclusions / pins / blocked times / filters /
/// sort (schedule.json), and the generated timetables. Views read it as `app.scheduleTab`.
///
/// Banner access: the class search is the PUBLIC one (no sign-in), through `BannerClient` on an anonymous ephemeral
/// URLSession. Signing in is optional and only for "Export to Banner…" (ScheduleModel+Export): the user signs in on
/// UNC Charlotte's own page in a WebKit sheet, and the export — after the user confirms — creates ONE new Plan Ahead
/// plan in that session. Every request is checked by `BannerRequestGuard`; registration is never possible.
@MainActor
@Observable
final class ScheduleModel {
    static let logger = Logger(subsystem: "org.thuban.planner", category: "schedule")
    /// Section cache entries older than this are refreshed automatically when shown.
    static let sectionMaxAge: TimeInterval = 6 * 3600
    static let termsMaxAge: TimeInterval = 12 * 3600
    /// Pause between two class searches (Banner is a shared university service).
    static let fetchDelay: UInt64 = 450_000_000

    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored let store: TimetableStore
    @ObservationIgnored var client = BannerClient()
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var fetchQueue: [String] = []

    /// No network at all (the smoke run): sample terms / sections, never Banner.
    var offline: Bool

    private(set) var isActivated = false
    private(set) var document: TimetableDocument = .empty
    private(set) var cache = BannerCache()
    /// schedule.json exists but couldn't be read: nothing is saved over it.
    private(set) var documentError: String?

    private(set) var termsPhase: SchedulePhase = .idle
    private(set) var selectedTermCode: String?

    private(set) var fetching: Set<String> = []
    private(set) var sectionErrors: [String: String] = [:]
    /// A network problem from the last fetch (shown with Retry).
    private(set) var networkError: String?

    /// "Block times" mode: dragging on the grid adds a block; clicking one edits it.
    var blockMode = false
    /// Sidebar: the course whose sections are expanded.
    var expandedCourse: String?
    /// The class detail sheet (nil = closed).
    var detail: ScheduleClassDetailItem?
    /// The sort popover is open.
    var sortMenuOpen = false

    // Sign-in and export (see ScheduleModel+Export.swift).
    /// UNC Charlotte sign-in state (the app's own WebKit store; never a password, never another browser's cookies).
    var auth: ScheduleAuth = .signedOut
    /// The sign-in sheet is open.
    var showSignIn = false
    /// The export sheet's state (nil = closed).
    var exportDraft: ScheduleExportDraft?
    /// Open the export once the sign-in sheet closes signed in.
    @ObservationIgnored var exportAfterSignIn = false
    @ObservationIgnored var exporter: BannerPlanExporter?
    @ObservationIgnored var exportTask: Task<Void, Never>?

    /// Rate My Professors lookups and cache.
    let ratings: ScheduleRatings
    /// CRN → professor rating for the term's loaded sections (from the RMP cache).
    private(set) var ratingTable = TimetableRatings.empty

    private(set) var rows: [ScheduleCourseRow] = []
    private(set) var result: TimetableResult = .empty
    /// Courses left out of generation because their sections aren't loaded (or failed to load).
    private(set) var missingCourses: [String] = []

    init(store: TimetableStore = TimetableStore(), offline: Bool = false) {
        self.store = store
        self.offline = offline
        ratings = ScheduleRatings(store: RMPCacheStore(directory: store.directory), offline: offline)
        ratings.onChange = { [weak self] in self?.ratingsChanged() }
    }

    // MARK: Lifecycle

    /// First time the tab shows: read schedule.json + the cache, then the term list.
    func activate() {
        guard !isActivated else { return }
        isActivated = true
        do {
            document = try store.loadDocument()
        } catch {
            documentError = error.localizedDescription
            Self.logger.error("schedule.json unreadable: \(error.localizedDescription, privacy: .public)")
        }
        cache = store.loadCache()
        if offline {
            seedOfflineSample()
            return
        }
        checkStoredSignIn()
        loadTerms()
    }

    // MARK: Terms

    /// The picker's terms: the newest six Banner lists, plus the selected and the calendar term.
    var pickerTerms: [BannerTerm] {
        let all = cache.terms
        var shown = Array(all.prefix(6))
        let calendarCode = app.flatMap { BannerTermCode.code(forTermKey: $0.calendarTermKey) }
        for code in [selectedTermCode, calendarCode].compactMap({ $0 }) where !shown.contains(where: { $0.code == code }) {
            if let term = all.first(where: { $0.code == code }) { shown.append(term) }
        }
        return shown.sorted { $0.code > $1.code }
    }

    var selectedTerm: BannerTerm? { selectedTermCode.flatMap { code in cache.terms.first { $0.code == code } } }

    var selectedTermLabel: String {
        selectedTerm?.description ?? selectedTermCode.flatMap(BannerTermCode.termKey).map(TermKey.label) ?? "Choose a term"
    }

    func loadTerms(force: Bool = false) {
        if offline { return }
        let fresh = cache.termsFetchedAt.map { Date().timeIntervalSince($0) < Self.termsMaxAge } ?? false
        if !cache.terms.isEmpty, fresh, !force {
            chooseDefaultTerm()
            return
        }
        if !cache.terms.isEmpty { chooseDefaultTerm() }
        termsPhase = .loading
        Task { [weak self] in
            guard let self else { return }
            do {
                let terms = try await self.client.terms()
                self.cache.terms = terms
                self.cache.termsFetchedAt = Date()
                self.saveCache()
                self.termsPhase = .idle
                self.networkError = nil
                self.chooseDefaultTerm()
            } catch {
                self.termsPhase = .failed(error.localizedDescription)
                if self.cache.terms.isEmpty { self.networkError = error.localizedDescription }
            }
        }
    }

    /// The last term used, else the next term Thuban's route plans, else the calendar term, else the newest.
    private func chooseDefaultTerm() {
        let codes = Set(cache.terms.map(\.code))
        if let code = selectedTermCode, codes.contains(code) { refreshRows(); return }
        var pick: String?
        if let last = document.lastTermCode, codes.contains(last) { pick = last }
        if pick == nil, let app {
            pick = app.schedule.plannedTerms.lazy.compactMap { BannerTermCode.code(forTermKey: $0.key) }.first { codes.contains($0) }
        }
        if pick == nil, let app, let code = BannerTermCode.code(forTermKey: app.calendarTermKey), codes.contains(code) { pick = code }
        if pick == nil { pick = cache.terms.first?.code }
        if let pick { selectTerm(pick, remember: false) }
    }

    func selectTerm(_ code: String, remember: Bool = true) {
        guard code != selectedTermCode else { return }
        selectedTermCode = code
        blockMode = false
        expandedCourse = nil
        if remember { updateDocument { $0.lastTermCode = code } }
        refreshRows()
        fetchMissingSections()
    }

    // MARK: Per-term state

    /// The selected term's choices (defaults when the term was never opened).
    var state: TimetableTermState {
        guard let code = selectedTermCode else { return TimetableTermState() }
        return document.state(code)
    }

    /// Changes the selected term's state, saves schedule.json, rebuilds the rows and the timetables.
    func updateState(regenerate: Bool = true, _ change: (inout TimetableTermState) -> Void) {
        guard let code = selectedTermCode else { return }
        updateDocument { doc in
            var s = doc.state(code)
            change(&s)
            doc.terms[code] = s
        }
        if regenerate { refreshRows() }
    }

    private func updateDocument(_ change: (inout TimetableDocument) -> Void) {
        var copy = document
        change(&copy)
        guard copy != document else { return }
        document = copy
        guard documentError == nil, !offline else { return }
        do { try store.saveDocument(copy) } catch {
            Self.logger.error("schedule.json save failed: \(error.localizedDescription, privacy: .public)")
            app?.saveError = error.localizedDescription
        }
    }

    private func saveCache() {
        guard !offline else { return }
        do { try store.saveCache(cache) } catch {
            Self.logger.error("cache save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Courses

    /// Rebuilds the course rows for the selected term and regenerates the timetables.
    func refreshRows() {
        guard let code = selectedTermCode else { rows = []; regenerate(); return }
        let s = state
        var list: [ScheduleCourseRow] = []
        func add(_ raw: String, title: String, credits: Double?, origin: ScheduleCourseRow.Origin) {
            guard let canonical = BannerText.canonicalCourseCode(raw) else { return }
            guard !s.removedCourses.contains(canonical), !list.contains(where: { $0.code == canonical }) else { return }
            let entry = cache.sections(term: code, course: canonical)
            let pin = s.pins[canonical]
            let fetchedTitle = entry?.sections.first?.title
            list.append(ScheduleCourseRow(code: canonical, title: title.isEmpty ? (fetchedTitle ?? "") : title,
                                          credits: credits ?? entry?.sections.first?.credits, origin: origin,
                                          pinnedCRN: pin, sections: entry?.sections, linkedSets: entry?.linkedSets ?? [:],
                                          fetchedAt: entry?.fetchedAt, isFetching: fetching.contains(canonical), error: sectionErrors[canonical]))
        }
        for course in routeCourses(termCode: code) { add(course.code, title: course.title, credits: course.credits, origin: .route) }
        for extra in s.addedCourses {
            let entry = cache.sections(term: code, course: extra)
            add(extra, title: entry?.sections.first?.title ?? "", credits: nil, origin: .added)
        }
        rows = list
        regenerate()
    }

    /// The classes Thuban's route places in (or recorded for) the term.
    func routeCourses(termCode: String) -> [Course] {
        guard let app, let key = BannerTermCode.termKey(termCode) else { return [] }
        let ids = app.schedule.board.first { $0.key == key }?.courseIds ?? app.courses(inTerm: key).map(\.id)
        return ids.compactMap { app.course($0) }.filter { !$0.code.isEmpty }
    }

    /// Adds a course by code ("MEGR 2144"); returns an error message for bad input.
    @discardableResult
    func addCourse(_ text: String) -> String? {
        guard let canonical = BannerText.canonicalCourseCode(text) else { return "Type a course code like MEGR 2144." }
        if rows.contains(where: { $0.code == canonical }) { return "\(canonical) is already in this term." }
        updateState {
            $0.removedCourses.removeAll { $0 == canonical }
            if !$0.addedCourses.contains(canonical) { $0.addedCourses.append(canonical) }
            $0.selectedIndex = 0
        }
        fetchMissingSections()
        return nil
    }

    func removeCourse(_ code: String) {
        updateState {
            $0.addedCourses.removeAll { $0 == code }
            if !$0.removedCourses.contains(code) { $0.removedCourses.append(code) }
            $0.selectedIndex = 0
        }
    }

    /// Brings back every course removed from this term.
    func restoreRemovedCourses() {
        updateState { $0.removedCourses = []; $0.selectedIndex = 0 }
        fetchMissingSections()
    }

    // MARK: Sections

    func isExcluded(_ crn: String) -> Bool { state.excludedCRNs.contains(crn) }

    func setIncluded(_ crn: String, _ included: Bool) {
        updateState {
            if included { $0.excludedCRNs.removeAll { $0 == crn } } else if !$0.excludedCRNs.contains(crn) { $0.excludedCRNs.append(crn) }
            $0.selectedIndex = 0
        }
    }

    /// Includes / excludes every section of a course.
    func setAllIncluded(_ row: ScheduleCourseRow, _ included: Bool) {
        let crns = row.sections?.map(\.crn) ?? []
        updateState { s in
            s.excludedCRNs.removeAll { crns.contains($0) }
            if !included { s.excludedCRNs.append(contentsOf: crns) }
            s.selectedIndex = 0
        }
    }

    /// Pins a section (nil unpins).
    func setPin(_ row: ScheduleCourseRow, crn: String?) {
        updateState { s in
            if let crn {
                s.pins[row.code] = crn
                s.excludedCRNs.removeAll { $0 == crn }
            } else {
                s.pins[row.code] = nil
            }
            s.selectedIndex = 0
        }
    }

    /// Fetches sections for every row that has none (or a stale entry).
    func fetchMissingSections() {
        guard let code = selectedTermCode else { return }
        let now = Date()
        let stale = rows.filter { row in
            guard let fetched = row.fetchedAt else { return true }
            return now.timeIntervalSince(fetched) > Self.sectionMaxAge
        }.map(\.code)
        enqueue(stale, term: code)
    }

    /// Refresh: fetch every course of the term again.
    func refreshAllSections() {
        guard let code = selectedTermCode else { return }
        networkError = nil
        enqueue(rows.map(\.code), term: code)
    }

    func retryCourse(_ course: String) {
        guard let code = selectedTermCode else { return }
        enqueue([course], term: code)
    }

    private func enqueue(_ courses: [String], term: String) {
        guard !offline else { return }
        for course in courses where !fetchQueue.contains("\(term)|\(course)") { fetchQueue.append("\(term)|\(course)") }
        guard fetchTask == nil, !fetchQueue.isEmpty else { refreshRows(); return }
        fetchTask = Task { [weak self] in
            await self?.drainQueue()
            self?.fetchTask = nil
        }
    }

    /// Sequential, throttled class searches. Each result is cached and the timetables regenerate as rows arrive.
    private func drainQueue() async {
        var first = true
        while !fetchQueue.isEmpty {
            let item = fetchQueue.removeFirst()
            let parts = item.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let split = BannerText.splitCourseCode(parts[1]) else { continue }
            let (term, course) = (parts[0], parts[1])
            if !first { try? await Task.sleep(nanoseconds: Self.fetchDelay) }
            first = false
            fetching.insert(course)
            if term == selectedTermCode { refreshRows() }
            do {
                let sections = try await client.sections(subject: split.subject, courseNumber: split.number, term: term)
                var linked: [String: [[BannerSection]]] = [:]
                for section in sections.filter(\.isLinked).prefix(12) {
                    try? await Task.sleep(nanoseconds: Self.fetchDelay / 2)
                    if let sets = try? await client.linkedSections(term: term, crn: section.crn), !sets.isEmpty { linked[section.crn] = sets }
                }
                cache.store(.init(fetchedAt: Date(), sections: sections, linkedSets: linked), term: term, course: course)
                sectionErrors[course] = nil
                networkError = nil
                saveCache()
            } catch {
                sectionErrors[course] = error.localizedDescription
                switch error as? BannerError {
                case .network?, nil: networkError = error.localizedDescription
                default: break
                }
            }
            fetching.remove(course)
            if term == selectedTermCode { refreshRows() }
        }
    }

    // MARK: Generation

    private func regenerate() {
        guard selectedTermCode != nil else { result = .empty; missingCourses = []; return }
        let s = state
        var courses: [TimetableCourse] = []
        var missing: [String] = []
        for row in rows {
            guard let sections = row.sections else { missing.append(row.code); continue }
            courses.append(TimetableCourse(code: row.code, title: row.title,
                                           choices: TimetableChoice.build(sections: sections, linkedSets: row.linkedSets),
                                           excludedCRNs: Set(s.excludedCRNs), pinnedCRN: row.pinnedCRN))
        }
        missingCourses = missing
        ratingTable = buildRatingTable()
        let fresh = TimetableGenerator.generate(courses: courses, blocks: s.blocks, filters: s.filters, sorts: s.sorts, ratings: ratingTable)
        if fresh != result { result = fresh }
        if s.sorts.contains(.highestRated) { lookUpAllProfessors() }
    }

    // MARK: Professor ratings

    /// Every section of the term's loaded courses (for the rating table and bulk lookups).
    private var allSections: [BannerSection] {
        rows.flatMap { row in (row.sections ?? []) + row.linkedSets.values.flatMap { $0.flatMap { $0 } } }
    }

    private func buildRatingTable() -> TimetableRatings {
        TimetableRatings.build(sections: allSections) { [ratings] name, section in ratings.match(name, subject: section.subject) }
    }

    /// New RMP answers: rebuild the table and, when the rating sort is on, re-sort (keeping the timetable on screen).
    private func ratingsChanged() {
        let table = buildRatingTable()
        guard table != ratingTable else { return }
        ratingTable = table
        guard state.sorts.contains(.highestRated), !result.options.isEmpty else { return }
        let shownId = currentOption?.id
        var resorted = result
        resorted.options = TimetableGenerator.sorted(result.options, by: state.sorts, ratings: table)
        result = resorted
        // On the best timetable, stay on the (new) best; after browsing, keep the one on screen.
        if selectedIndex > 0, let shownId, let index = resorted.options.firstIndex(where: { $0.id == shownId }), index != selectedIndex {
            updateState(regenerate: false) { $0.selectedIndex = index }
        }
    }

    /// Looks up every distinct instructor of the term's loaded sections (cache first; sequential, paced). Only
    /// called for the "Highest professor rating" sort or the explicit "Look up professor ratings" button.
    func lookUpAllProfessors() {
        ratings.requestAll(allSections.flatMap(\.instructors))
    }

    /// The current timetable's professor score (credit-weighted), when any of its courses is rated.
    var currentRatingScore: TimetableRatings.Score? { currentOption.flatMap { ratingTable.score($0) } }

    // MARK: Class detail

    func showDetail(_ section: BannerSection, course: String) {
        detail = ScheduleClassDetailItem(section: section, course: course)
    }

    /// The usual date range of a course's meetings this term (most common start / end) — meeting dates that differ
    /// are shown in the detail.
    func typicalDates(course: String) -> (start: Int?, end: Int?) {
        let meetings = rows.first { $0.code == course }?.sections?.flatMap(\.meetings) ?? []
        var counts: [String: (Int?, Int?, Int)] = [:]
        for m in meetings {
            let key = "\(m.startDate ?? 0)-\(m.endDate ?? 0)"
            counts[key] = (m.startDate, m.endDate, (counts[key]?.2 ?? 0) + 1)
        }
        guard let best = counts.values.max(by: { $0.2 != $1.2 ? $0.2 < $1.2 : ($0.0 ?? 0) > ($1.0 ?? 0) }) else { return (nil, nil) }
        return (best.0, best.1)
    }

    var optionCount: Int { result.options.count }

    /// The timetable on screen (clamped).
    var selectedIndex: Int { min(max(0, state.selectedIndex), max(0, result.options.count - 1)) }

    var currentOption: TimetableOption? { result.options.isEmpty ? nil : result.options[selectedIndex] }

    func showOption(_ index: Int) {
        guard !result.options.isEmpty else { return }
        let clamped = (index % result.options.count + result.options.count) % result.options.count
        updateState(regenerate: false) { $0.selectedIndex = clamped }
    }

    func nextOption() { showOption(selectedIndex + 1) }
    func previousOption() { showOption(selectedIndex - 1) }

    func setSort(_ sort: TimetableSort) { setSorts([sort]) }

    /// Replaces the sort priority list (normalized: no duplicates, never empty).
    func setSorts(_ sorts: [TimetableSort]) {
        let list = TimetableSort.normalizedList(sorts)
        guard list != state.sorts else { return }
        updateState { $0.sorts = list; $0.selectedIndex = 0 }
    }

    /// Checking a criterion appends it to the priority list; unchecking removes it (never the last one).
    func toggleSort(_ sort: TimetableSort) {
        var list = state.sorts
        if let i = list.firstIndex(of: sort) {
            guard list.count > 1 else { return }
            list.remove(at: i)
        } else {
            list.append(sort)
        }
        setSorts(list)
    }

    /// Moves an active criterion up (-1) or down (+1) in the priority list.
    func moveSort(_ sort: TimetableSort, by offset: Int) {
        var list = state.sorts
        guard let i = list.firstIndex(of: sort) else { return }
        let j = i + offset
        guard list.indices.contains(j) else { return }
        list.swapAt(i, j)
        setSorts(list)
    }

    func resetSorts() { setSorts(TimetableSort.defaultList) }

    func setFilters(_ change: (inout TimetableFilters) -> Void) {
        updateState { s in change(&s.filters); s.selectedIndex = 0 }
    }

    /// Campuses the term's sections are offered on (for the campus filter).
    var campuses: [String] {
        Array(Set(rows.flatMap { $0.sections?.map(\.campus) ?? [] }.filter { !$0.isEmpty })).sorted()
    }

    /// "20263 20262 …" for pasting into Banner's registration (the user registers there themselves).
    var currentCRNText: String { currentOption?.crns.joined(separator: ", ") ?? "" }

    func copyCRNs() {
        guard let option = currentOption else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(option.crns.joined(separator: ", "), forType: .string)
    }

    // MARK: Blocks

    var blocks: [TimetableBlock] { state.blocks }

    @discardableResult
    func addBlock(day: BannerWeekday, start: Int, end: Int, label: String = "") -> TimetableBlock? {
        guard end - start >= 15 else { return nil }
        let block = TimetableBlock(day: day, start: start, end: end, label: label)
        updateState { $0.blocks.append(block); $0.selectedIndex = 0 }
        return block
    }

    func updateBlock(_ block: TimetableBlock) {
        updateState { s in
            if let i = s.blocks.firstIndex(where: { $0.id == block.id }) { s.blocks[i] = block }
            s.selectedIndex = 0
        }
    }

    func removeBlock(_ id: String) { updateState { $0.blocks.removeAll { $0.id == id }; $0.selectedIndex = 0 } }

    func clearBlocks() { updateState { $0.blocks = []; $0.selectedIndex = 0 } }

    // MARK: Colours

    /// Stable colour slot per course (its position in the term's list).
    func colorIndex(of course: String) -> Int { rows.firstIndex { $0.code == course } ?? 0 }

    // MARK: Offline sample (smoke)

    /// Sample terms and sections for every course of the route's terms, so the smoke run never touches the network.
    func seedOfflineSample() {
        guard let app else { return }
        let next = app.schedule.plannedTerms.first?.key ?? TermKey.next(app.calendarTermKey)
        cache.terms = BannerSampleData.terms(around: next)
        cache.termsFetchedAt = Date()
        for term in cache.terms {
            for course in routeCourses(termCode: term.code) {
                cache.store(.init(fetchedAt: Date(), sections: BannerSampleData.sections(course: course.code, title: course.title,
                                                                                         credits: course.credits, termCode: term.code)),
                            term: term.code, course: course.code)
            }
        }
        selectedTermCode = nil
        selectTerm(BannerTermCode.code(forTermKey: next) ?? cache.terms[0].code, remember: false)
    }

    /// SMOKE ONLY: replaces the in-memory state wholesale (never saved: `offline` is on in a smoke run).
    func smokeSet(blockMode: Bool? = nil, _ change: ((inout TimetableTermState) -> Void)? = nil) {
        guard offline else { return }
        if let blockMode { self.blockMode = blockMode }
        if let change { updateState(change) }
    }

    /// SMOKE ONLY: opens the class detail for the current timetable's first class with these instructors (and, when
    /// `examMeeting`, a second meeting on its own dates).
    func smokeShowDetail(instructors: [String], examMeeting: Bool = false) {
        guard offline, let pick = currentOption?.picks.first, var section = pick.choice.sections.first else { return }
        section.instructors = instructors
        if examMeeting, let end = section.meetings.first?.endDate {
            section.meetings.append(BannerMeeting(days: [.saturday], begin: 9 * 60, end: 11 * 60 + 30, startDate: end - 3, endDate: end - 3,
                                                  building: "EPIC", buildingDescription: "EPIC Building", room: "G256", meetingType: "Final Exam"))
        }
        showDetail(section, course: pick.course)
    }

    /// SMOKE ONLY: drops the term's cached sections for one course (a "no sections" state) or restores the sample.
    func smokeSetSections(_ sections: [BannerSection]?, course: String) {
        guard offline, let code = selectedTermCode else { return }
        if let sections {
            cache.store(.init(fetchedAt: Date(), sections: sections), term: code, course: course)
        } else {
            cache.sections.removeValue(forKey: BannerCache.key(term: code, course: course))
        }
        refreshRows()
    }
}
