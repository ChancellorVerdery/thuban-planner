import Foundation
import ThubanPlannerCore

/// The Planner's class-table filter ("All · To take · Taken").
enum PlannerClassFilter: String, CaseIterable, Hashable {
    case all, toTake, taken

    var label: String {
        switch self {
        case .all: return "All"
        case .toTake: return "To take"
        case .taken: return "Taken"
        }
    }
}

/// One group of rows in the class table: a recorded term (in rank order) or "To take" (last).
struct PlannerClassGroup: Identifiable, Hashable {
    /// The recorded term key, or nil for "To take".
    var termKey: String?
    var courses: [Course]
    var id: String { termKey ?? "to-take" }
    var credits: Double { courses.reduce(0) { $0 + $1.credits } }
}

/// Read-only queries for the Planner screen. Derived from `data` / `schedule`; nothing is cached.
extension AppModel {
    /// The class table's groups: every recorded term that holds a visible class (rank order), then "To take". A class
    /// whose term key names no recorded term is grouped under that key after the recorded ones. Inside a group,
    /// classes sort by code (empty codes first, so a new class shows at the top), then title.
    func plannerClassGroups(filter: PlannerClassFilter, search: String) -> [PlannerClassGroup] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visible = courses.filter { course in
            switch filter {
            case .all: break
            case .toTake: if course.isTaken { return false }
            case .taken: if !course.isTaken { return false }
            }
            guard !needle.isEmpty else { return true }
            return course.code.lowercased().contains(needle) || course.title.lowercased().contains(needle)
                || course.code.lowercased().replacingOccurrences(of: " ", with: "").contains(needle.replacingOccurrences(of: " ", with: ""))
        }
        var byTerm: [String: [Course]] = [:]
        var toTake: [Course] = []
        for course in visible {
            if let key = course.term { byTerm[key, default: []].append(course) } else { toTake.append(course) }
        }
        let recordedKeys = terms.map(\.key)
        let orphanKeys = byTerm.keys.filter { !recordedKeys.contains($0) }.sorted { TermKey.rank($0) < TermKey.rank($1) }
        var groups: [PlannerClassGroup] = []
        for key in recordedKeys + orphanKeys {
            if let list = byTerm[key], !list.isEmpty {
                groups.append(PlannerClassGroup(termKey: key, courses: list.sorted(by: Self.plannerCourseOrder)))
            }
        }
        if !toTake.isEmpty { groups.append(PlannerClassGroup(termKey: nil, courses: toTake.sorted(by: Self.plannerCourseOrder))) }
        return groups
    }

    /// Code (natural order, empty first), then title, then id — stable across edits.
    nonisolated static func plannerCourseOrder(_ a: Course, _ b: Course) -> Bool {
        if a.code.isEmpty != b.code.isEmpty { return a.code.isEmpty }
        let byCode = a.code.localizedStandardCompare(b.code)
        if byCode != .orderedSame { return byCode == .orderedAscending }
        let byTitle = a.title.localizedStandardCompare(b.title)
        if byTitle != .orderedSame { return byTitle == .orderedAscending }
        return a.id < b.id
    }

    /// Credits recorded in a semester (the chip's "15 cr").
    func plannerCredits(inTerm key: String) -> Double {
        courses(inTerm: key).reduce(0) { $0 + $1.credits }
    }

    /// The Add-semester form's defaults: the calendar term (season, year).
    var plannerDefaultNewTerm: (season: Season, year: Int) {
        let parsed = TermKey.parse(calendarTermKey)
        return (parsed.season ?? .fall, Int(parsed.year))
    }

    /// "STAT 3128 isn’t in your plan, so it’s ignored." (nil when every requirement resolves).
    var plannerUnknownRefsNote: String? {
        let refs = unknownRefs
        guard !refs.isEmpty else { return nil }
        if refs.count == 1 { return "\(refs[0]) isn’t in your plan, so it’s ignored." }
        let list = refs.count == 2 ? "\(refs[0]) and \(refs[1])" : refs.dropLast().joined(separator: ", ") + " and \(refs.last!)"
        return "\(list) aren’t in your plan, so they’re ignored."
    }

    /// Classes that name this code as a requirement (for the remove confirmation).
    func plannerDependentsCount(of course: Course) -> Int { dependents(of: course).count }
}

extension AppModel {
    /// The class ids in the order the table shows them (for ↑ / ↓).
    func plannerVisibleCourseIds(filter: PlannerClassFilter, search: String) -> [String] {
        plannerClassGroups(filter: filter, search: search).flatMap { $0.courses.map(\.id) }
    }

    /// Counts for the filter's segments.
    func plannerCount(_ filter: PlannerClassFilter) -> Int {
        switch filter {
        case .all: return courses.count
        case .toTake: return toTake.count
        case .taken: return taken.count
        }
    }

    /// A requirement ref as the table shows it: the ref and the class it names (nil = unknown).
    func plannerResolvedRefs(_ refs: [String]) -> [(ref: String, course: Course?)] {
        refs.map { ($0, course(forRef: $0)) }
    }

    /// "Its 6 classes go back to To take." (nil when the semester has none).
    func plannerRemoveTermMessage(_ key: String) -> String? {
        let n = courses(inTerm: key).count
        guard n > 0 else { return nil }
        return n == 1 ? "Its 1 class goes back to To take." : "Its \(n) classes go back to To take."
    }

    /// The remove-class confirmation's message: who depends on it.
    func plannerRemoveCourseMessage(_ course: Course) -> String {
        let n = plannerDependentsCount(of: course)
        if n == 0 { return "This can’t be undone." }
        return n == 1 ? "1 class lists it as a requirement; that requirement will be ignored." : "\(n) classes list it as a requirement; those requirements will be ignored."
    }

    /// "3 more terms" / "1 more term" (nil when nothing is scheduled).
    var plannerMoreTermsText: String? {
        let n = schedule.termsToFinish
        guard n > 0, !toTake.isEmpty else { return nil }
        return n == 1 ? "1 more term" : "\(n) more terms"
    }
}

extension AppModel {
    /// "Fall 2025" / "To take" — a class-table group's title.
    func plannerGroupTitle(_ group: PlannerClassGroup) -> String {
        group.termKey.map(termLabel) ?? "To take"
    }

    /// "6 classes · 16 cr" — a class-table group's caption.
    func plannerGroupCaption(_ group: PlannerClassGroup) -> String {
        let n = group.courses.count
        return "\(n) class\(n == 1 ? "" : "es") · \(creditsText(group.credits)) cr"
    }

    /// True when the group is the current semester.
    func plannerGroupIsCurrent(_ group: PlannerClassGroup) -> Bool {
        guard let key = group.termKey else { return false }
        return term(key)?.current == true
    }

    /// A requirement list as its editable text ("MATH 1241, PHYS 2101").
    nonisolated static func plannerRefsText(_ refs: [String]) -> String { refs.joined(separator: ", ") }

    /// Credits as the numeric cell shows / parses them. nil = not a valid credit count (keeps the old value).
    nonisolated static func plannerParseCredits(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// The Finishes tile: value and caption.
    var plannerFinishTile: (value: String, caption: String, tone: ChipKind) {
        if courses.isEmpty { return ("—", "Add classes to plan a route", .neutral) }
        if toTake.isEmpty { return ("Done", "Nothing left to schedule", .pos) }
        let unplaced = schedule.unplaceable.count
        if unplaced > 0 {
            return (gradTermLabel ?? "—", "\(unplaced) class\(unplaced == 1 ? "" : "es") can’t be placed", .neg)
        }
        return (gradTermLabel ?? "—", plannerMoreTermsText ?? "", .neutral)
    }

    /// Recorded semesters, newest last, with their taken credits.
    var plannerSemesterChips: [(term: Term, credits: Double, count: Int)] {
        terms.map { term in
            let list = courses(inTerm: term.key)
            return (term, list.reduce(0) { $0 + $1.credits }, list.count)
        }
    }

    /// True when the add-semester form's term already exists.
    func plannerTermExists(season: Season, year: Int) -> Bool {
        term(TermKey.make(season, year)) != nil
    }
}
