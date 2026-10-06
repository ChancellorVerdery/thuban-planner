import Foundation
import ThubanPlannerCore

/// A requirement ref as the class detail sheet / planner shows it: the text the user typed and the class it names
/// (nil = not in the plan; the scheduler ignores it).
struct ResolvedRequirement: Hashable, Identifiable {
    var ref: String
    var kind: RequirementKind
    var course: Course?
    var id: String { "\(kind.rawValue)|\(ref)" }
}

/// Read-only views of the plan and the route. Everything here is derived from `data` / `schedule` — no caches.
extension AppModel {
    // MARK: Plan

    var courses: [Course] { data.courses }
    var terms: [Term] { data.terms }
    var settings: PlannerSettings { data.settings }
    var currentTerm: Term? { data.currentTerm }
    var toTake: [Course] { data.toTake }
    var taken: [Course] { data.taken }
    var disabledTerms: [String] { data.disabledTerms }

    func course(_ id: String) -> Course? { data.course(id) }
    func term(_ key: String) -> Term? { data.term(key) }
    func courses(inTerm key: String) -> [Course] { data.courses(inTerm: key) }
    func isDisabled(_ termKey: String) -> Bool { data.isDisabled(termKey) }

    /// Credits of the classes still to take / taken (incl. current).
    var creditsToTake: Double { toTake.reduce(0) { $0 + $1.credits } }
    var creditsTaken: Double { taken.reduce(0) { $0 + $1.credits } }
    var creditsTotal: Double { courses.reduce(0) { $0 + $1.credits } }

    /// Transfer / AP credit (term "transfer") — counted in `taken` / `creditsTaken`.
    var transferCourses: [Course] { data.transferCourses }
    var transferCredits: Double { transferCourses.reduce(0) { $0 + $1.credits } }

    /// The class a requirement code names (case- and space-insensitive; the last class with that code wins).
    func course(forRef ref: String) -> Course? { data.course(forRef: ref) }

    /// A class's prerequisites then corequisites, each resolved to the class it names (or nil).
    func requirements(of course: Course) -> [ResolvedRequirement] {
        course.prereqs.map { ResolvedRequirement(ref: $0, kind: .prereq, course: data.course(forRef: $0)) }
            + course.coreqs.map { ResolvedRequirement(ref: $0, kind: .coreq, course: data.course(forRef: $0)) }
    }

    /// Classes that list `course` as a prerequisite or corequisite ("Required by").
    func dependents(of course: Course) -> [(course: Course, kind: RequirementKind)] {
        guard !course.code.isEmpty else { return [] }
        let key = Course.normalizeRef(course.code)
        // Only when `course` is the class the code resolves to (the last with that code), like the scheduler.
        guard data.course(forRef: course.code)?.id == course.id else { return [] }
        var out: [(Course, RequirementKind)] = []
        for other in courses where other.id != course.id {
            if other.prereqs.contains(where: { Course.normalizeRef($0) == key }) { out.append((other, .prereq)) }
            else if other.coreqs.contains(where: { Course.normalizeRef($0) == key }) { out.append((other, .coreq)) }
        }
        return out
    }

    /// Requirement refs across the plan that match no class.
    var unknownRefs: [String] { data.unknownRefs }

    // MARK: Route

    /// The one-line summary (Atlas `planStatus`): "12 to take · 38 credits · 3 more terms · finishes Fall 2027".
    var planStatus: String { Scheduler.planStatus(data, schedule) }

    /// Scheduler warnings ("Couldn't place: … — check for missing prerequisites or a prerequisite cycle.").
    var warnings: [String] { schedule.warnings }

    /// "Spring 2028" — the last column of the route (nil when the board is empty).
    var gradTermLabel: String? { schedule.gradTermLabel }

    /// Where a class stands: taken / in progress / planned (with its term) / unplaceable.
    func status(of courseId: String) -> CourseStatus { schedule.status(of: courseId) }

    /// The term a class is (or will be) in, from the route — recorded term for taken classes, planned term otherwise.
    func routeTerm(of courseId: String) -> BoardTerm? { schedule.boardTerm(of: courseId) }

    /// Summer terms for the "Summer terms" toggles (Atlas `upcomingSummers`): the next few summers + any switched off.
    var upcomingSummers: [String] { Scheduler.upcomingSummers(data, now: now, calendar: calendar) }

    /// The calendar term containing today ("fall-2026"), for the Add-semester form's defaults.
    var calendarTermKey: String { TermKey.current(now: now, calendar: calendar) }

    // MARK: Text

    /// "3" / "1.5" — credits as Atlas prints them.
    func creditsText(_ credits: Double) -> String { JS.numberString(credits) }

    /// "Fall 2025", or "Transfer credit" for transfer credit.
    func termLabel(_ key: String) -> String { TermKey.displayLabel(key) }
}
