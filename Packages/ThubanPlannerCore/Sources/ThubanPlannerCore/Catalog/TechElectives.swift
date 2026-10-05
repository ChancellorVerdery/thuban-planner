import Foundation

/// Technical electives for a program dataset (UNC Charlotte BSME 2025-26): which electives exist, which ran
/// recently, which are in the plan, what each still needs, and the requirement tracker ("2 of 4 chosen · 2 of 3 MEGR").
/// Pure; the app feeds it the plan, the dataset and the offerings.
public enum TechElectives {
    /// Tag on a class chosen as a technical elective.
    public static let electiveTag = "tech-elective"
    /// Tag prefix on a class added as a prerequisite for an elective ("prereq:PHYS 4242").
    public static let prereqTagPrefix = "prereq:"

    public static func prereqTag(for code: String) -> String { prereqTagPrefix + CourseCode.normalize(code) }

    /// Where an elective stands with the plan.
    public enum PlanState: Hashable, Sendable {
        case notInPlan
        case taken(term: String)
        case planned
    }

    /// Readiness to add.
    public enum Readiness: Hashable, Sendable {
        /// Already in the plan.
        case inPlan
        /// Every requirement is in the plan.
        case ready
        /// `count` classes must be added; `chain` is the longest path to the elective ("PHYS 4241 → PHYS 3220").
        case needs(count: Int, chain: [String])
    }

    public struct Status: Hashable, Sendable, Identifiable {
        public var code: String
        public var title: String
        public var credits: Double
        public var isMEGR: Bool
        public var elective: CatalogDataset.Elective
        public var offering: CourseOfferings.Summary
        public var planState: PlanState
        /// Counts toward the requirement (in the plan, and its condition met).
        public var counts: Bool
        public var readiness: Readiness
        /// Classes that would be added with the default choices, prerequisites first (the elective itself excluded).
        public var missing: [String]
        public var notes: [String]
        public var catalogURL: String?

        public var id: String { code }
        public var isOffered: Bool { offering.isOffered }
    }

    public struct Progress: Hashable, Sendable {
        public var chosen: [String]
        public var required: Int
        public var megr: Int
        public var requiredMEGR: Int
        public var credits: Double
        public var requiredCredits: Double

        public var isComplete: Bool { chosen.count >= required && megr >= requiredMEGR }
        /// "2 of 4 chosen · 2 of 3 MEGR".
        public var text: String { "\(min(chosen.count, required)) of \(required) chosen · \(min(megr, requiredMEGR)) of \(requiredMEGR) MEGR" }
    }

    // MARK: Status

    /// One status per elective of the dataset, in the catalog's order (DegreeWorks-only codes after).
    public static func statuses(dataset: CatalogDataset, data: PlannerData, offerings: CourseOfferings, window: CourseOfferings.Window) -> [Status] {
        let index = PlanCourseIndex(data)
        let resolver = RequirementChainResolver(dataset: dataset, data: data) { offerings.summary(for: $0, window: window) }
        return dataset.electives.map { elective in
            let catalog = dataset.course(elective.code)
            let inPlan = index.find(elective.code)
            let planState: PlanState = inPlan.map { $0.term.map { .taken(term: $0) } ?? .planned } ?? .notInPlan
            let readiness: Readiness
            var missing: [String] = []
            if inPlan != nil {
                readiness = .inPlan
            } else {
                let plan = resolver.resolve([elective.code])
                missing = plan.prerequisiteAdditions.map(\.code)
                readiness = missing.isEmpty ? .ready : .needs(count: missing.count, chain: longestChain(plan.roots.first))
            }
            var notes: [String] = []
            if let condition = elective.condition { notes.append(condition) }
            notes += catalog?.notes ?? []
            return Status(code: elective.code, title: catalog?.title ?? inPlan?.title ?? "", credits: catalog?.credits ?? 3,
                          isMEGR: elective.megr, elective: elective, offering: offerings.summary(for: elective.code, window: window),
                          planState: planState, counts: inPlan != nil && conditionMet(elective, index: index),
                          readiness: readiness, missing: missing, notes: notes, catalogURL: catalog?.catalogURL)
        }
    }

    /// MEGR 3221 counts only when MEGR 3216 fills the design elective (catalog condition).
    static func conditionMet(_ elective: CatalogDataset.Elective, index: PlanCourseIndex) -> Bool {
        guard let condition = elective.condition else { return true }
        let codes = CatalogRequirementParser.tokens(condition).compactMap { t -> String? in
            if case .code(let c) = t { return c }
            return nil
        }.filter { CourseCode.key($0) != CourseCode.key(elective.code) }
        return codes.allSatisfy { index.contains($0) }
    }

    /// The deepest path of additions from the elective down, reported bottom-most last: ["PHYS 4241", "PHYS 3220"].
    static func longestChain(_ root: ChainNode?) -> [String] {
        guard let root else { return [] }
        func walk(_ node: ChainNode) -> [String] {
            let best = node.children.filter(\.isAddition).map(walk).max { $0.count < $1.count } ?? []
            return [node.code] + best
        }
        return Array(walk(root).dropFirst())
    }

    // MARK: Progress

    public static func progress(dataset: CatalogDataset, data: PlannerData) -> Progress {
        let index = PlanCourseIndex(data)
        var chosen: [String] = []
        var megr = 0
        var credits = 0.0
        for elective in dataset.electives {
            guard let course = index.find(elective.code), conditionMet(elective, index: index), !chosen.contains(elective.code) else { continue }
            chosen.append(elective.code)
            if elective.megr { megr += 1 }
            credits += course.credits
        }
        let rule = dataset.program.techElectives
        return Progress(chosen: chosen, required: rule.count, megr: megr, requiredMEGR: rule.minimumMEGR, credits: credits,
                        requiredCredits: rule.credits)
    }

    // MARK: Apply

    /// The classes `plan` adds, ready to append (To take, tagged). `makeId` mints ids.
    public static func courses(for plan: ChainPlan, makeId: () -> String = { PlannerID.make("c") }) -> [Course] {
        plan.additions.map { addition in
            var tags: [String] = []
            if addition.isTarget { tags.append(electiveTag) }
            for target in addition.requiredFor where target != addition.code { tags.append(prereqTag(for: target)) }
            return Course(id: makeId(), code: addition.code, title: addition.title, credits: addition.credits,
                          prereqs: addition.prereqs, coreqs: addition.coreqs, summerOk: addition.summerOk, term: nil,
                          tags: tags.isEmpty ? nil : tags)
        }
    }

    /// Appends the plan's classes to `data`; classes whose code is already in the plan are skipped (never touched).
    /// Returns the ids added.
    @discardableResult
    public static func apply(_ plan: ChainPlan, to data: inout PlannerData, makeId: () -> String = { PlannerID.make("c") }) -> [String] {
        let index = PlanCourseIndex(data)
        var added: [String] = []
        for course in courses(for: plan, makeId: makeId) where !index.contains(course.code) {
            data.courses.append(course)
            added.append(course.id)
        }
        return added
    }

    /// Marks an existing class as a chosen elective (adds the tag; nothing else changes).
    public static func tagAsElective(_ id: String, in data: inout PlannerData) {
        guard let i = data.courses.firstIndex(where: { $0.id == id }) else { return }
        var tags = data.courses[i].tags ?? []
        if !tags.contains(electiveTag) { tags.append(electiveTag) }
        data.courses[i].tags = tags
    }

    // MARK: Remove

    /// Removing the elective `code` (still to take): the elective's class plus the To-take classes that were added
    /// only for it (tagged "prereq:<code>", no other elective tag of a class still in the plan, and not required by
    /// a class that stays). Taken classes are never offered for removal.
    public static func removal(of code: String, data: PlannerData) -> (elective: Course?, prerequisites: [Course]) {
        let index = PlanCourseIndex(data)
        guard let elective = index.find(code), elective.term == nil else { return (nil, []) }
        let tag = prereqTag(for: elective.code)
        var candidates = data.courses.filter { course in
            guard course.term == nil, course.id != elective.id, let tags = course.tags, tags.contains(tag) else { return false }
            let otherTargets = tags.filter { $0.hasPrefix(prereqTagPrefix) && $0 != tag }.map { String($0.dropFirst(prereqTagPrefix.count)) }
            return !otherTargets.contains { index.contains($0) }
        }
        // Drop candidates still required by a class that stays (iterate to a fixed point).
        var changed = true
        while changed {
            changed = false
            let removing = Set(candidates.map(\.id) + [elective.id])
            let staying = data.courses.filter { !removing.contains($0.id) }
            let needed = Set(staying.flatMap { ($0.prereqs + $0.coreqs).map(CourseCode.key) })
            let kept = candidates.filter { !needed.contains(CourseCode.key($0.code)) }
            if kept.count != candidates.count {
                candidates = kept
                changed = true
            }
        }
        return (elective, candidates)
    }
}
