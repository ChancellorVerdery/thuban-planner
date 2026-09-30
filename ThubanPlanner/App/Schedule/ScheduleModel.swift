import AppKit
import Foundation
import Observation
import ThubanPlannerCore
import os

/// A course row in the Schedule sidebar: where it came from, its (effective) pin, and what Banner said about it.
struct ScheduleCourseRow: Identifiable, Hashable {
    enum Origin: Hashable { case plan, route, added }

    /// Canonical "MEGR 2144".
    var code: String
    var title: String
    var credits: Double?
    var origin: Origin
    /// The CRN the Banner plan names for this course (nil = course-level plan item).
    var planCRN: String?
    /// The pin in force (the user's own, else the plan's unless unpinned).
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

/// Where the Schedule tab is with Banner sign-in.
enum ScheduleAuth: Equatable {
    /// Not checked yet (cookies exist from an earlier sign-in).
    case unknown
    case checking
    case signedOut
    /// Was signed in; the session ended.
    case expired
    case signedIn(name: String?)

    var isSignedIn: Bool { if case .signedIn = self { return true }; return false }
}

enum SchedulePhase: Equatable {
    case idle, loading
    case failed(String)
}

/// The Schedule tab's state: the Banner term, where the courses come from (the Banner plan or Thuban's route),
/// their sections (fetched one course at a time, cached), the user's exclusions / pins / blocked times / filters /
/// sort (schedule.json), and the generated timetables. Views read it as `app.scheduleTab`.
///
/// Banner access: the PUBLIC class search goes through `BannerClient` (URLSession, an anonymous ephemeral session —
/// never the user's cookies); anything that needs the student's sign-in (Plan Ahead, the student's name) runs inside
/// WebKit on the app's own persistent website data store (`BannerPlanReader`, `ScheduleSignInSheet`). Every request
/// is checked by `BannerRequestGuard`; the tab is strictly read-only.
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
    @ObservationIgnored private var reader: BannerPlanReader?
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

    var auth: ScheduleAuth = .signedOut
    private(set) var planPhase: SchedulePhase = .idle
    var showSignIn = false

    private(set) var fetching: Set<String> = []
    private(set) var sectionErrors: [String: String] = [:]
    /// A network problem from the last fetch (shown with Retry).
    private(set) var networkError: String?

    /// "Block times" mode: dragging on the grid adds a block; clicking one edits it.
    var blockMode = false
    /// Sidebar: the course whose sections are expanded.
    var expandedCourse: String?

    private(set) var rows: [ScheduleCourseRow] = []
    private(set) var result: TimetableResult = .empty
    /// Courses left out of generation because their sections aren't loaded (or failed to load).
    private(set) var missingCourses: [String] = []

    init(store: TimetableStore = TimetableStore(), offline: Bool = false) {
        self.store = store
        self.offline = offline
    }

    // MARK: Lifecycle

    /// First time the tab shows: read schedule.json + the cache, the term list, the session state.
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
        if !cache.plans.isEmpty { auth = .unknown }
        Task { [weak self] in
            guard let self else { return }
            if await BannerWebKit.hasUNCCCookies() {
                if self.auth == .signedOut { self.auth = .unknown }
            } else {
                self.auth = .signedOut
            }
        }
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
        if state.source == .bannerPlan, cache.plans[code] == nil, auth != .signedOut { loadPlan() }
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

    // MARK: Source and plan

    func setSource(_ source: TimetableSource) {
        updateState { $0.source = source; $0.selectedIndex = 0 }
        if source == .bannerPlan, let code = selectedTermCode, cache.plans[code] == nil, auth != .signedOut { loadPlan() }
        fetchMissingSections()
    }

    var plans: [BannerPlan] { selectedTermCode.flatMap { cache.plans[$0]?.plans } ?? [] }
    var plansFetchedAt: Date? { selectedTermCode.flatMap { cache.plans[$0]?.fetchedAt } }

    /// The plan in use: the chosen one, else the preferred (plans are sorted preferred first).
    var currentPlan: BannerPlan? {
        let all = plans
        if let seq = state.planSequence, let plan = all.first(where: { $0.sequenceNumber == seq }) { return plan }
        return all.first
    }

    func selectPlan(_ sequence: Int) {
        updateState { $0.planSequence = sequence; $0.selectedIndex = 0 }
        fetchMissingSections()
    }

    /// Reads the student's plans for the selected term in the hidden web view (needs sign-in).
    func loadPlan() {
        guard let code = selectedTermCode else { return }
        if offline { return }
        planPhase = .loading
        if !auth.isSignedIn { auth = .checking }
        Task { [weak self] in
            guard let self else { return }
            let reader = self.reader ?? BannerPlanReader()
            self.reader = reader
            do {
                let output = try await reader.readPlans(termCode: code)
                var entry = BannerCache.PlanEntry(fetchedAt: Date(), plans: output.plans, studentName: output.studentName)
                if entry.studentName == nil { entry.studentName = self.studentName }
                self.cache.plans[code] = entry
                self.saveCache()
                self.auth = .signedIn(name: entry.studentName)
                self.planPhase = .idle
                self.refreshRows()
                self.fetchMissingSections()
            } catch BannerError.signedOut {
                let had = await BannerWebKit.hasUNCCCookies()
                self.auth = had || self.cache.plans[code] != nil ? .expired : .signedOut
                self.planPhase = .failed(BannerError.signedOut.localizedDescription)
            } catch {
                if self.auth == .checking { self.auth = .unknown }
                self.planPhase = .failed(error.localizedDescription)
            }
        }
    }

    /// The student's name from the latest plan read (or the sign-in sheet).
    var studentName: String? {
        if case .signedIn(let name?) = auth { return name }
        return cache.plans.values.max(by: { $0.fetchedAt < $1.fetchedAt })?.studentName
    }

    /// Called by the sign-in sheet when a signed-in Banner page loaded.
    func didSignIn(name: String?) {
        auth = .signedIn(name: name ?? studentName)
    }

    /// The sheet closed after signing in: read the plan now.
    func afterSignInSheet() {
        if auth.isSignedIn || auth == .unknown, state.source == .bannerPlan { loadPlan() }
    }

    func signOut() {
        Task { [weak self] in
            await BannerWebKit.signOut()
            guard let self else { return }
            self.reader = nil
            self.auth = .signedOut
            self.cache.plans = [:]
            self.saveCache()
            self.planPhase = .idle
            self.refreshRows()
        }
    }

    // MARK: Courses

    /// Rebuilds the course rows for the selected term and regenerates the timetables.
    func refreshRows() {
        guard let code = selectedTermCode else { rows = []; regenerate(); return }
        let s = state
        var list: [ScheduleCourseRow] = []
        func add(_ raw: String, title: String, credits: Double?, origin: ScheduleCourseRow.Origin, planCRN: String? = nil) {
            guard let canonical = BannerText.canonicalCourseCode(raw) else { return }
            guard !s.removedCourses.contains(canonical), !list.contains(where: { $0.code == canonical }) else { return }
            let entry = cache.sections(term: code, course: canonical)
            let pin = s.pins[canonical] ?? (s.unpinnedPlanCourses.contains(canonical) ? nil : planCRN)
            let fetchedTitle = entry?.sections.first?.title
            list.append(ScheduleCourseRow(code: canonical, title: title.isEmpty ? (fetchedTitle ?? "") : title,
                                          credits: credits ?? entry?.sections.first?.credits, origin: origin, planCRN: planCRN,
                                          pinnedCRN: pin, sections: entry?.sections, linkedSets: entry?.linkedSets ?? [:],
                                          fetchedAt: entry?.fetchedAt, isFetching: fetching.contains(canonical), error: sectionErrors[canonical]))
        }
        switch s.source {
        case .route:
            for course in routeCourses(termCode: code) { add(course.code, title: course.title, credits: course.credits, origin: .route) }
        case .bannerPlan:
            for course in currentPlan?.courses(inTerm: code) ?? [] {
                add(course.courseCode, title: course.title, credits: course.credits, origin: .plan, planCRN: course.crn)
            }
        }
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

    /// Pins a section (nil unpins; unpinning a plan's CRN remembers that).
    func setPin(_ row: ScheduleCourseRow, crn: String?) {
        updateState { s in
            if let crn {
                s.pins[row.code] = crn
                s.excludedCRNs.removeAll { $0 == crn }
                s.unpinnedPlanCourses.removeAll { $0 == row.code }
            } else {
                s.pins[row.code] = nil
                if row.planCRN != nil, !s.unpinnedPlanCourses.contains(row.code) { s.unpinnedPlanCourses.append(row.code) }
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
        if state.source == .bannerPlan, auth != .signedOut { loadPlan() }
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
        let fresh = TimetableGenerator.generate(courses: courses, blocks: s.blocks, filters: s.filters, sort: s.sort)
        if fresh != result { result = fresh }
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

    func setSort(_ sort: TimetableSort) { updateState { $0.sort = sort; $0.selectedIndex = 0 } }

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
        if let code = BannerTermCode.code(forTermKey: next) {
            let courses = routeCourses(termCode: code).prefix(4).enumerated().map { i, c in
                BannerPlanCourse(term: code, subject: BannerText.splitCourseCode(c.code)?.subject ?? "",
                                 courseNumber: BannerText.splitCourseCode(c.code)?.number ?? "", title: c.title,
                                 crn: i == 0 ? cache.sections(term: code, course: c.code)?.sections.first?.crn : nil, credits: c.credits)
            }
            cache.plans[code] = .init(fetchedAt: Date(), plans: [BannerPlan(sequenceNumber: 1, description: "Spring plan", preferred: true,
                                                                            totalCredits: 12, courses: Array(courses))],
                                      studentName: "Sample Student")
        }
        selectedTermCode = nil
        selectTerm(BannerTermCode.code(forTermKey: next) ?? cache.terms[0].code, remember: false)
    }

    /// SMOKE ONLY: replaces the in-memory state wholesale (never saved: `offline` is on in a smoke run).
    func smokeSet(auth: ScheduleAuth? = nil, blockMode: Bool? = nil, _ change: ((inout TimetableTermState) -> Void)? = nil) {
        guard offline else { return }
        if let auth { self.auth = auth }
        if let blockMode { self.blockMode = blockMode }
        if let change { updateState(change) }
    }

    @ObservationIgnored private var smokeStashedPlans: [String: BannerCache.PlanEntry]?

    /// SMOKE ONLY: hides the sample Banner plan (the signed-out state) and brings it back.
    func smokeHidePlans(_ hide: Bool) {
        guard offline else { return }
        if hide {
            smokeStashedPlans = cache.plans
            cache.plans = [:]
        } else if let stashed = smokeStashedPlans {
            cache.plans = stashed
            smokeStashedPlans = nil
        }
        refreshRows()
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
