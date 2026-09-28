import Foundation

/// Atlas's degree-route scheduler (`scheduleDegree` in atlas-ui/src/page/course.js), ported line for line so the
/// same plan and "now" give the same board, edges, unplaceable list, warning text, terms-to-finish and graduation
/// term.
///
/// Greedy critical-path packing: walk terms forward from the last recorded term; in each, fill up to the credit cap
/// with the eligible classes that gate the most downstream work (depth desc, then credits desc, then code by
/// `localeCompare`), pulling a class's unmet same-term corequisites in as an atomic group. Prerequisites must be in
/// an EARLIER term, summer terms take only summer-offered classes under the summer cap, disabled terms are skipped,
/// and at most 60 terms are generated. Strategies: soonest (use summers), soonest with summers only when they
/// finish strictly earlier, and an even load (the same number of terms with a lighter cap, falling back to full
/// caps rather than dropping a big class).
///
/// Fidelity notes:
/// - The class order uses `V8Sort` (V8's TimSort) with a lazily memoizing depth comparator, like Atlas; in a
///   requirement cycle the memoized depths depend on the comparator call order, so the port reproduces it.
/// - Codes compare with `JS.localeCompare` (ICU root collation, exact for ASCII codes).
/// - Courses are tracked by array index, so duplicate ids behave as in Atlas (the LAST course with an id stands for it).
/// - The input is used as given (Atlas schedules the `loadCourse()`-normalized blob; `AppModel` keeps `data`
///   normalized). `now` / `calendar` only matter when no term is recorded (the route then starts after the term
///   containing `now`).
public enum Scheduler {
    /// Maximum number of consecutive terms one packing run walks (Atlas's guard).
    public static let termGuard = 60

    public static func scheduleDegree(_ s: PlannerData, now: Date = Date(), calendar: Calendar = .current) -> Schedule {
        let courses = s.courses
        var byId: [String: Int] = [:]
        for (i, c) in courses.enumerated() { byId[c.id] = i }
        var byCode: [String: Int] = [:]
        for (i, c) in courses.enumerated() where !c.code.isEmpty { byCode[norm(c.code)] = i }
        func idOf(_ ref: String) -> String? { byCode[norm(ref)].map { courses[$0].id } }
        // Requirement code-refs resolved to ids that exist in the plan (unknown refs are dropped).
        var preCache: [Int: [String]] = [:], coCache: [Int: [String]] = [:]
        func preOf(_ i: Int) -> [String] {
            if let hit = preCache[i] { return hit }
            let ids = courses[i].prereqs.compactMap(idOf).filter { !$0.isEmpty }
            preCache[i] = ids
            return ids
        }
        func coOf(_ i: Int) -> [String] {
            if let hit = coCache[i] { return hit }
            let ids = courses[i].coreqs.compactMap(idOf).filter { !$0.isEmpty }
            coCache[i] = ids
            return ids
        }

        // Downstream weight: how much work is gated behind a class (longer = do sooner).
        var dependents: [String: [String]] = [:]
        for c in courses { dependents[c.id] = [] }
        for i in courses.indices {
            for r in preOf(i) + coOf(i) { dependents[r]?.append(courses[i].id) }
        }
        let depth = DepthMemo(dependents: dependents)

        let disabled = Set(s.disabledTerms)
        let donePrior = Set(courses.filter { isTaken($0) }.map(\.id)) // past + current → before term 1
        let startCursor = s.terms.last?.key ?? TermKey.previous(TermKey.current(now: now, calendar: calendar))
        let remaining = courses.indices.filter { !isTaken(courses[$0]) }
        let g = s.settings
        func capFor(_ key: String) -> Double { TermKey.parse(key).seasonText == "summer" ? g.summerMax : g.maxCredits }

        struct PlannedTerm { var key: String; var courseIds: [String]; var credits: Double }
        struct Plan { var terms: [PlannedTerm]; var unplaceable: [String] }

        // One packing run over generated future terms.
        func runPlan(useSummers: Bool, capScale: Double = 1) -> Plan {
            var prior = donePrior
            var rem = remaining
            V8Sort.sort(&rem) { a, b in
                // JS: (depthOf(b.id) - depthOf(a.id)) || (b.credits - a.credits) || norm(a.code).localeCompare(norm(b.code))
                let db = depth.of(courses[b].id)
                let da = depth.of(courses[a].id)
                return JS.or(Double(db - da), JS.or(courses[b].credits - courses[a].credits,
                                                    Double(JS.localeCompare(norm(courses[a].code), norm(courses[b].code)))))
            }
            var remSet = Set(rem.map { courses[$0].id })
            var terms: [PlannedTerm] = []
            var cursor = startCursor
            var guardCount = 0
            while !rem.isEmpty && guardCount < termGuard {
                defer { guardCount += 1 }
                cursor = TermKey.next(cursor)
                let isSummer = TermKey.parse(cursor).seasonText == "summer"
                if disabled.contains(cursor) { continue }
                if isSummer && !useSummers { continue }
                let cap = JS.max(0, JS.round(capFor(cursor) * capScale))
                var picked: [Int] = []
                var credits = 0.0
                var added = true
                while added {
                    added = false
                    for c in rem {
                        if picked.contains(c) { continue }
                        // Atomic group = c + its unmet same-or-earlier coreqs still to take. Members already picked
                        // THIS term satisfy the coreq (same term), so only the not-yet-picked ones are added.
                        let group = groupClosure(c, id: courses[c].id, coOf: coOf, prior: prior, remSet: remSet, byId: byId)
                        let newOnes = group.filter { !picked.contains($0) }
                        if newOnes.isEmpty { continue }
                        if !newOnes.allSatisfy({ x in preOf(x).allSatisfy { prior.contains($0) } }) { continue } // prereqs earlier
                        if isSummer && !newOnes.allSatisfy({ courses[$0].summerOk }) { continue } // summer offering
                        let addCred = newOnes.reduce(0.0) { $0 + courses[$1].credits }
                        if credits + addCred > cap { continue }
                        for x in newOnes { picked.append(x); credits += courses[x].credits }
                        added = true
                    }
                }
                if !picked.isEmpty {
                    terms.append(PlannedTerm(key: cursor, courseIds: picked.map { courses[$0].id }, credits: credits))
                    for c in picked { prior.insert(courses[c].id); remSet.remove(courses[c].id) }
                    rem = rem.filter { remSet.contains(courses[$0].id) }
                }
            }
            return Plan(terms: terms, unplaceable: rem.map { courses[$0].id })
        }

        let plan: Plan
        switch g.strategy {
        case .even:
            let soonest = runPlan(useSummers: false)
            if !soonest.unplaceable.isEmpty {
                plan = runPlan(useSummers: true) // couldn't finish without summers → use them
            } else {
                // Same number of terms with a lighter per-term cap; if that can't place everything (the scaled cap
                // fell below one big class), keep the full-cap plan rather than failing.
                let totalRem = remaining.reduce(0.0) { $0 + courses[$1].credits }
                let target = (totalRem / Double(Swift.max(1, soonest.terms.count))).rounded(.up)
                let light = runPlan(useSummers: false, capScale: JS.min(1, target / g.maxCredits))
                plan = light.unplaceable.isEmpty ? light : soonest
            }
        case .soonestOptionalSummer:
            let withSummers = runPlan(useSummers: true)
            let without = runPlan(useSummers: false)
            func finishRank(_ p: Plan) -> Double {
                if !p.unplaceable.isEmpty { return .infinity }
                return p.terms.last.map { TermKey.rank($0.key) } ?? -.infinity
            }
            plan = finishRank(withSummers) < finishRank(without) ? withSummers : without // summers only if strictly earlier
        case .soonestSummer:
            plan = runPlan(useSummers: true)
        }

        // Full board: recorded terms (past / current) + planned future terms, chronological.
        let userTerms = s.terms.map { t in
            BoardTerm(key: t.key, season: t.season, year: t.year, current: t.current, kind: t.current ? .current : .past,
                      courseIds: courses.filter { $0.term == t.key }.map(\.id), credits: 0)
        }
        let planned = plan.terms.map { t -> BoardTerm in
            let parsed = TermKey.parse(t.key)
            return BoardTerm(key: t.key, season: parsed.season ?? .spring, year: parsed.year, current: false, kind: .future,
                             courseIds: t.courseIds, credits: t.credits)
        }
        var board = V8Sort.sorted(userTerms + planned) { a, b in TermKey.rank(a.key) - TermKey.rank(b.key) }
        for i in board.indices {
            board[i].credits = board[i].courseIds.reduce(0.0) { sum, id in sum + JS.or(byId[id].map { courses[$0].credits } ?? 0, 0) }
        }

        // Prereq / coreq edges for the board (only between placed courses).
        var termOfCourse: [String: String] = [:]
        for t in board { for id in t.courseIds { termOfCourse[id] = t.key } }
        var edges: [RouteEdge] = []
        for i in courses.indices {
            for (kind, ids) in [(RequirementKind.prereq, preOf(i)), (.coreq, coOf(i))] {
                for r in ids where termOfCourse[r] != nil && termOfCourse[courses[i].id] != nil {
                    edges.append(RouteEdge(from: r, to: courses[i].id, kind: kind))
                }
            }
        }

        var warnings: [String] = []
        if !plan.unplaceable.isEmpty {
            let names = plan.unplaceable.map { id -> String in
                guard let c = byId[id].map({ courses[$0] }) else { return id }
                if !c.code.isEmpty { return c.code }
                if !c.title.isEmpty { return c.title }
                return id
            }
            warnings.append("Couldn't place: \(names.joined(separator: ", ")) — check for missing prerequisites or a prerequisite cycle.")
        }
        return Schedule(board: board, edges: edges, unplaceable: plan.unplaceable, warnings: warnings,
                        termsToFinish: plan.terms.count, gradTerm: board.last?.key)
    }

    // MARK: Helpers shared with the UI (Atlas courseui.js)

    /// Summer terms in the planning horizon, for the "Summer terms" toggles: the next 15 terms after the last
    /// recorded term (or after the current calendar term when none is recorded) plus any summer already switched
    /// off, sorted, first five (Atlas `upcomingSummers`).
    public static func upcomingSummers(_ s: PlannerData, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let start = s.terms.last?.key ?? TermKey.current(now: now, calendar: calendar)
        var out: [String] = []
        var seen = Set<String>()
        func add(_ key: String) { if seen.insert(key).inserted { out.append(key) } }
        for key in s.disabledTerms where TermKey.parse(key).seasonText == "summer" { add(key) }
        var cursor = start
        for _ in 0 ..< 15 {
            cursor = TermKey.next(cursor)
            if TermKey.parse(cursor).seasonText == "summer" { add(cursor) }
        }
        return Array(V8Sort.sorted(out) { TermKey.rank($0) - TermKey.rank($1) }.prefix(5))
    }

    /// The one-line plan summary (Atlas `planStatus`): "12 to take · 38 credits · 3 more terms · finishes Fall 2027",
    /// or "40 classes · nothing left to schedule".
    public static func planStatus(_ s: PlannerData, _ schedule: Schedule) -> String {
        let remaining = s.courses.filter { !isTaken($0) }
        let credits = remaining.reduce(0.0) { $0 + $1.credits }
        if remaining.isEmpty { return "\(s.courses.count) classes · nothing left to schedule" }
        let grad = (schedule.gradTerm != nil && schedule.termsToFinish != 0) ? " · finishes \(TermKey.label(schedule.gradTerm!))" : ""
        let n = schedule.termsToFinish
        return "\(remaining.count) to take · \(JS.numberString(credits)) credits · \(n) more term\(n == 1 ? "" : "s")\(grad)"
    }

    // MARK: Internals

    /// Atlas `norm`: trimmed, lower-cased.
    static func norm(_ text: String) -> String { JS.trim(text).lowercased() }

    /// JS truthiness of `c.term`.
    static func isTaken(_ c: Course) -> Bool { !(c.term ?? "").isEmpty }

    /// c plus the still-to-take corequisites (same-or-earlier) not already satisfied by an earlier term — they must
    /// share c's term, so they schedule as one unit. Follows the coreq chain; cycle-safe. Returns indices of the
    /// courses standing for each id (the last course with that id), in discovery order.
    static func groupClosure(_ c: Int, id courseId: String, coOf: (Int) -> [String], prior: Set<String>, remSet: Set<String>,
                             byId: [String: Int]) -> [Int] {
        var group: [String] = [courseId]
        var inGroup: Set<String> = [courseId]
        var stack: [Int] = [c]
        while let x = stack.popLast() {
            for r in coOf(x) {
                if prior.contains(r) || inGroup.contains(r) || !remSet.contains(r) { continue } // satisfied, seen, or not to take
                group.append(r)
                inGroup.insert(r)
                if let i = byId[r] { stack.append(i) }
            }
        }
        return group.compactMap { byId[$0] }
    }
}

/// Atlas `depthOf`: 1 + the deepest dependent, memoized on first computation; a class met again while its own
/// depth is being computed counts 0 (cycle guard) — so in a cycle the answer depends on who was asked first.
final class DepthMemo {
    private let dependents: [String: [String]]
    private var memo: [String: Int] = [:]

    init(dependents: [String: [String]]) { self.dependents = dependents }

    func of(_ id: String) -> Int {
        var seen = Set<String>()
        return compute(id, &seen)
    }

    private func compute(_ id: String, _ seen: inout Set<String>) -> Int {
        if let hit = memo[id] { return hit }
        if seen.contains(id) { return 0 }
        seen.insert(id)
        var deepest = 0
        for x in dependents[id] ?? [] { deepest = Swift.max(deepest, compute(x, &seen)) }
        seen.remove(id)
        let d = 1 + deepest
        memo[id] = d
        return d
    }
}
