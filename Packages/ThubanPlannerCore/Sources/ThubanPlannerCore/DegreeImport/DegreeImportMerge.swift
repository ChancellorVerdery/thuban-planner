import Foundation

/// What importing a degree document would change. Merge rules:
///
/// - Only ADDS classes; never modifies or removes a class already in the plan (taken or to take) — not its term,
///   credits, requirements or title.
/// - A required class is skipped when the plan already has it: same code (case / space-insensitive) or a known
///   equivalent (`CourseCode.equivalents`, e.g. PHYS 1101L for PHYS 2101L).
/// - Choice groups ("Select four of the following") are never added automatically; the preview lists them and adds
///   only the options the user picks. A group whose plan count already meets its pick is shown as satisfied.
/// - Missing credits / titles / requirements are filled from the bundled catalog dataset when it knows the class.
/// - Requirements become codes: a single-option group keeps its code; an OR-group keeps the option that is in the
///   plan or being added (else it is left out — the scheduler would ignore an unknown code anyway).
/// - Added classes are To take, tagged "program:<name>". Importing the same document twice adds nothing.
public struct DegreeImportPlan: Hashable, Sendable {
    /// A required class the plan already has.
    public struct Match: Hashable, Sendable {
        public var documentCode: String
        public var planCode: String
    }

    public struct Candidate: Hashable, Sendable, Identifiable {
        public var code: String
        public var title: String
        public var credits: Double
        public var prereqs: [String]
        public var coreqs: [String]
        public var notes: [String]
        public var section: String?
        /// Title / credits / requirements came from the bundled catalog (the document didn't say).
        public var filledFromCatalog: Bool
        public var id: String { code }
    }

    public struct Choice: Hashable, Sendable, Identifiable {
        public var group: DegreeChoiceGroup
        /// Options already in the plan (codes as the plan spells them).
        public var inPlan: [String]
        /// Options the user may add (not in the plan).
        public var available: [Candidate]
        public var isSatisfied: Bool { inPlan.count >= group.pick }
        public var remaining: Int { max(0, group.pick - inPlan.count) }
        public var id: String { group.id }
    }

    public var documentName: String
    public var programName: String?
    public var kind: ParsedDegreeDocument.Kind
    /// Required classes the document lists.
    public var requiredCount: Int
    /// Required classes the plan already has.
    public var alreadyInPlan: [Match]
    public var toAdd: [Candidate]
    public var choices: [Choice]
    public var warnings: [String]

    /// "program:Minor in Mathematics" (or the document name when no program was found).
    public var programTag: String { "program:" + (programName ?? documentName) }
}

public enum DegreeImportMerge {
    public static func plan(_ document: ParsedDegreeDocument, documentName: String, data: PlannerData,
                            dataset: CatalogDataset? = CatalogDataset.bsme2025) -> DegreeImportPlan {
        let index = PlanCourseIndex(data)
        var already: [DegreeImportPlan.Match] = []
        var missing: [DegreeItem] = []
        for item in document.required {
            if let hit = index.find(item.code) { already.append(.init(documentCode: item.code, planCode: hit.code)) } else { missing.append(item) }
        }
        var choices: [DegreeImportPlan.Choice] = []
        // A class counts toward one requirement: required matches first, then each group in order takes up to its pick.
        var used = Set(already.map { CourseCode.key($0.planCode) })
        for group in document.choices {
            var inPlan: [String] = []
            for option in group.options {
                guard inPlan.count < group.pick, let hit = index.find(option.code)?.code, !used.contains(CourseCode.key(hit)) else { continue }
                inPlan.append(hit)
                used.insert(CourseCode.key(hit))
            }
            let available = group.options.filter { !index.contains($0.code) }
            choices.append(DegreeImportPlan.Choice(group: group, inPlan: inPlan, available: available.map { candidate($0, dataset: dataset) }))
        }
        // Requirements resolve against the plan plus everything this import may add.
        let adding = Set(missing.map { CourseCode.key($0.code) })
        let toAdd = missing.map { item -> DegreeImportPlan.Candidate in
            var c = candidate(item, dataset: dataset)
            c.prereqs = refs(c.prereqs, groups: groups(item, dataset: dataset).prereq, index: index, adding: adding)
            c.coreqs = refs(c.coreqs, groups: groups(item, dataset: dataset).coreq, index: index, adding: adding)
            return c
        }
        var warnings: [String] = []
        if !document.skippedLines.isEmpty {
            warnings += document.skippedLines.prefix(12).map { "Not read as a requirement: \($0)" }
            if document.skippedLines.count > 12 { warnings.append("… and \(document.skippedLines.count - 12) more lines.") }
        }
        if document.required.isEmpty && document.choices.isEmpty {
            warnings.insert("No course requirements were found in this document.", at: 0)
        }
        return DegreeImportPlan(documentName: documentName, programName: document.programName, kind: document.kind,
                                requiredCount: document.required.count, alreadyInPlan: already, toAdd: toAdd, choices: choices,
                                warnings: warnings)
    }

    static func groups(_ item: DegreeItem, dataset: CatalogDataset?) -> (prereq: [[String]], coreq: [[String]]) {
        if !item.prereqGroups.isEmpty || !item.coreqGroups.isEmpty { return (item.prereqGroups, item.coreqGroups) }
        guard let course = dataset?.course(item.code) else { return ([], []) }
        return (course.prereqGroups, course.sameTermGroups)
    }

    static func candidate(_ item: DegreeItem, dataset: CatalogDataset?) -> DegreeImportPlan.Candidate {
        let catalog = dataset?.course(item.code)
        let title = item.title.isEmpty ? (catalog?.title ?? "") : item.title
        let credits = item.credits ?? catalog?.credits ?? 3
        let g = groups(item, dataset: dataset)
        let catalogHasRequirements = !(catalog?.prereqGroups ?? []).isEmpty || !(catalog?.sameTermGroups ?? []).isEmpty
        let filled = (item.title.isEmpty && catalog != nil) || (item.credits == nil && catalog?.credits != nil)
            || (item.prereqGroups.isEmpty && item.coreqGroups.isEmpty && catalogHasRequirements)
        return DegreeImportPlan.Candidate(code: item.code, title: title, credits: credits,
                                          prereqs: g.prereq.compactMap { $0.count == 1 ? $0[0] : nil },
                                          coreqs: g.coreq.compactMap { $0.count == 1 ? $0[0] : nil },
                                          notes: item.notes, section: item.section, filledFromCatalog: filled)
    }

    /// Requirement groups → codes for the plan (see the type's rules).
    static func refs(_ fallback: [String], groups: [[String]], index: PlanCourseIndex, adding: Set<String>) -> [String] {
        var out: [String] = []
        for group in groups {
            if let hit = group.lazy.compactMap({ index.find($0)?.code }).first {
                out.append(hit)
            } else if let added = group.first(where: { adding.contains(CourseCode.key($0)) }) {
                out.append(CourseCode.normalize(added))
            } else if group.count == 1 {
                out.append(CourseCode.normalize(group[0]))
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert(CourseCode.key($0)).inserted }
    }

    /// Applies the user's selection: the candidates in `include` (by code) plus each choice's picked option codes.
    /// Classes already in the plan are skipped; nothing existing is touched. Returns the ids added.
    @discardableResult
    public static func apply(_ plan: DegreeImportPlan, include: Set<String>, picks: [String: [String]],
                             to data: inout PlannerData, makeId: () -> String = { PlannerID.make("c") }) -> [String] {
        var index = PlanCourseIndex(data)
        var added: [String] = []
        var candidates = plan.toAdd.filter { include.contains($0.code) }
        for choice in plan.choices {
            let wanted = Set((picks[choice.id] ?? []).map(CourseCode.key))
            candidates += choice.available.filter { wanted.contains(CourseCode.key($0.code)) }
        }
        for c in candidates where !index.contains(c.code) {
            let course = Course(id: makeId(), code: c.code, title: c.title, credits: c.credits, prereqs: c.prereqs, coreqs: c.coreqs,
                                summerOk: false, term: nil, tags: [plan.programTag])
            data.courses.append(course)
            added.append(course.id)
            index = PlanCourseIndex(data)
        }
        return added
    }
}
