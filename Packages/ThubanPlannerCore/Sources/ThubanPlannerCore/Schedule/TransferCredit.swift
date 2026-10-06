import Foundation

/// Transfer credit (Thuban-only, 2026-10-05): a class whose `term` is the reserved key `"transfer"` was earned
/// before the first semester (AP, IB, dual enrollment, community college). It is NOT a `Term` row (those need a
/// season and year), so Atlas's data model, normalization and scheduler need nothing new: `loadCourse()` keeps any
/// non-empty term string, and `scheduleDegree` treats every class with a non-empty term as done before planned term
/// 1 — prerequisites on a transfer class are met. Atlas simply draws it nowhere (status `.unscheduled`).
extension TermKey {
    /// The reserved term value of a transfer-credit class.
    public static let transfer = "transfer"

    /// True for the transfer-credit term value (compared like a JavaScript string).
    public static func isTransfer(_ key: String?) -> Bool {
        guard let key else { return false }
        return JSKey(key) == JSKey(transfer)
    }

    /// What the UI shows for a term value: "Transfer credit" for transfer, else Atlas's `termLabel` ("Fall 2025").
    /// `label` itself stays Atlas's function, untouched.
    public static func displayLabel(_ key: String) -> String {
        isTransfer(key) ? "Transfer credit" : label(key)
    }
}

extension Course {
    /// Transfer / AP credit (term "transfer"). Counts as taken (`isTaken` is true).
    public var isTransfer: Bool { TermKey.isTransfer(term) }
}

extension PlannerData {
    /// Transfer-credit classes, document order.
    public var transferCourses: [Course] { courses.filter(\.isTransfer) }

    /// Moves classes to transfer credit (term "transfer"). Unknown ids are ignored.
    public mutating func moveToTransfer(_ ids: Set<String>) {
        for i in courses.indices where ids.contains(courses[i].id) { courses[i].term = TermKey.transfer }
    }

    /// Every transfer-credit class goes back to "To take".
    public mutating func clearTransferCredit() {
        for i in courses.indices where courses[i].isTransfer { courses[i].term = nil }
    }
}

extension Scheduler {
    /// Thuban-only POST-STEP over Atlas's route: prepends a "Transfer credit" column (kind `.transfer`, key
    /// "transfer") holding every class whose term is "transfer" (document order, credits summed) and appends the
    /// requirement ribbons that START at a transfer class and end at any placed class (incl. another transfer class —
    /// a same-column coreq), resolved with the scheduler's own rules (codes case- / space-insensitive, the LAST class
    /// with a code wins, unknown refs ignored), in document order. A ribbon INTO a transfer class from a semester
    /// would run backwards and is not drawn. Everything Atlas computed — the rest of the board, its edges (kept as a
    /// prefix, same order), unplaceable, warnings, termsToFinish, gradTerm — is returned unchanged. No transfer class
    /// → the schedule is returned as is (so an Atlas document never gets the column).
    public static func withTransferColumn(_ schedule: Schedule, _ data: PlannerData) -> Schedule {
        let courses = data.courses
        let transferIdx = courses.indices.filter { courses[$0].isTransfer }
        guard !transferIdx.isEmpty else { return schedule }

        var seenIds = Set<JSKey>()
        var ids: [String] = []
        var credits = 0.0
        for i in transferIdx where seenIds.insert(JSKey(courses[i].id)).inserted {
            ids.append(courses[i].id)
            credits += courses[i].credits.isFinite ? courses[i].credits : 0
        }
        let column = BoardTerm(key: TermKey.transfer, season: .fall, year: 0, current: false, kind: .transfer,
                               courseIds: ids, credits: credits)

        var out = schedule
        out.board = [column] + schedule.board

        // Same resolution as the scheduler's `idOf`.
        var byCode: [JSKey: String] = [:]
        for c in courses where !c.code.isEmpty { byCode[JSKey(norm(c.code))] = c.id }
        var placed = Set<JSKey>()
        for t in out.board { for id in t.courseIds { placed.insert(JSKey(id)) } }
        let transferIds = Set(ids.map(JSKey.init))
        for c in courses where placed.contains(JSKey(c.id)) {
            for (kind, refs) in [(RequirementKind.prereq, c.prereqs), (.coreq, c.coreqs)] {
                for ref in refs {
                    guard let from = byCode[JSKey(norm(ref))], !from.isEmpty, transferIds.contains(JSKey(from)) else { continue }
                    out.edges.append(RouteEdge(from: from, to: c.id, kind: kind))
                }
            }
        }
        return out
    }
}
