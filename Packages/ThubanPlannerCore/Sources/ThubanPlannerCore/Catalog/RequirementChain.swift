import Foundation

/// The classes a plan already has, matched by code (case / space-insensitive, known equivalents included).
public struct PlanCourseIndex: Sendable {
    private var byKey: [String: Course] = [:]

    public init(_ data: PlannerData) {
        // The LAST class with a code wins, like the scheduler.
        for course in data.courses where !course.code.isEmpty { byKey[CourseCode.key(course.code)] = course }
    }

    /// The plan's class for `code`, or for a code equivalent to it.
    public func find(_ code: String) -> Course? {
        for candidate in CourseCode.equivalentCodes(code) {
            if let hit = byKey[CourseCode.key(candidate)] { return hit }
        }
        return nil
    }

    public func contains(_ code: String) -> Bool { find(code) != nil }
}

/// One node of the requirement tree shown before adding: the class, how it relates to its parent, and whether it is
/// already in the plan, will be added, or cannot be resolved.
public struct ChainNode: Hashable, Sendable, Identifiable {
    public enum State: Hashable, Sendable {
        /// Already in the plan: taken in `term`, or still to take (term nil).
        case inPlan(code: String, term: String?)
        /// Will be added.
        case add
        /// Will be added, already listed earlier in the tree (not expanded again).
        case addedAbove
        /// Not in the bundled catalog: added with what is known (code only), requirements unknown.
        case unknown
        /// A requirement cycle stops here.
        case cycle
    }

    public var id: String
    public var code: String
    public var title: String
    public var credits: Double
    /// How this class relates to its parent (nil for the elective itself).
    public var kind: RequirementKind?
    public var state: State
    /// When chosen from an OR-group: every option of that group, and the group's key for `choices`.
    public var alternatives: [String]
    public var groupKey: String?
    public var children: [ChainNode]

    public var isAddition: Bool {
        switch state {
        case .add, .unknown: return true
        default: return false
        }
    }
}

/// An OR-group the user can switch ("MATH 2171 or MATH 2241").
public struct ChainChoice: Hashable, Sendable, Identifiable {
    public var key: String
    /// The class whose requirement this is.
    public var owner: String
    public var kind: RequirementKind
    public var options: [String]
    public var chosen: String
    /// Additional classes each option would need (0 = already in the plan).
    public var costs: [String: Int]

    public var id: String { key }
}

/// A class the plan will gain.
public struct ChainAddition: Hashable, Sendable, Identifiable {
    public var code: String
    public var title: String
    public var credits: Double
    /// Codes (as the plan / the addition list spell them) that must be done earlier.
    public var prereqs: [String]
    /// Codes that must be done the same term or earlier.
    public var coreqs: [String]
    public var summerOk: Bool
    /// One of the classes asked for (not a prerequisite).
    public var isTarget: Bool
    /// The targets this class is added for.
    public var requiredFor: [String]
    public var notes: [String]
    public var inCatalog: Bool

    public var id: String { code }
}

/// What adding one or more classes (with every missing prerequisite / corequisite, recursively) would do.
public struct ChainPlan: Hashable, Sendable {
    public var targets: [String]
    public var roots: [ChainNode]
    /// In dependency order: prerequisites before the classes that need them.
    public var additions: [ChainAddition]
    public var choices: [ChainChoice]
    public var warnings: [String]

    public var credits: Double { additions.reduce(0) { $0 + $1.credits } }
    /// Additions that are not targets.
    public var prerequisiteAdditions: [ChainAddition] { additions.filter { !$0.isTarget } }
    public var isEmpty: Bool { additions.isEmpty }
}

/// Resolves requirement chains against the bundled catalog and the plan. Pure and deterministic.
///
/// - A requirement group is satisfied when any option is in the plan (taken or still to take — the scheduler orders
///   the rest) or already being added.
/// - Otherwise one option is chosen: the user's choice for that group (`choices[key]`) when it is one of its options,
///   else the option needing the fewest additional classes (ties: offered recently, in the catalog, listed first).
/// - The chosen option is resolved recursively; classes are added once (deduplicated across targets) in dependency
///   order; cycles stop with a warning; a class missing from the catalog is added by code with a warning.
public struct RequirementChainResolver: Sendable {
    public var dataset: CatalogDataset
    public var plan: PlanCourseIndex
    /// Offered recently (tie-break, `summerOk`, warnings). nil = unknown.
    public var offered: (@Sendable (String) -> CourseOfferings.Summary?)?

    public init(dataset: CatalogDataset, data: PlannerData, offered: (@Sendable (String) -> CourseOfferings.Summary?)? = nil) {
        self.dataset = dataset
        self.plan = PlanCourseIndex(data)
        self.offered = offered
    }

    public static func groupKey(owner: String, kind: RequirementKind, index: Int) -> String {
        "\(CourseCode.normalize(owner))#\(kind == .prereq ? "p" : "c")\(index)"
    }

    // MARK: Cost

    /// Additional classes `code` needs, itself included (0 when in the plan). Cycle-safe; memoized per call.
    public func cost(_ code: String) -> Int {
        var memo: [String: Int] = [:]
        return cost(CourseCode.normalize(code), stack: [], memo: &memo)
    }

    private func cost(_ code: String, stack: Set<String>, memo: inout [String: Int]) -> Int {
        if plan.contains(code) { return 0 }
        if let known = memo[code] { return known }
        guard let course = dataset.course(code) else { return 1 }
        if stack.contains(code) { return 1000 }
        var next = stack
        next.insert(code)
        var total = 1
        for group in course.prereqGroups + course.sameTermGroups {
            total += group.map { cost(CourseCode.normalize($0), stack: next, memo: &memo) }.min() ?? 0
        }
        total = min(total, 1000)
        memo[code] = total
        return total
    }

    private func best(_ options: [String]) -> String {
        let ranked = options.enumerated().map { index, option -> (String, Int, Int, Int, Int) in
            let code = CourseCode.normalize(option)
            let isOffered = offered?(code)?.isOffered ?? true
            return (code, cost(code), isOffered ? 0 : 1, dataset.course(code) == nil ? 1 : 0, index)
        }
        return ranked.min { a, b in (a.1, a.2, a.3, a.4) < (b.1, b.2, b.3, b.4) }!.0
    }

    // MARK: Resolve

    public func resolve(_ targets: [String], choices: [String: String] = [:]) -> ChainPlan {
        var state = Walk()
        var roots: [ChainNode] = []
        let normalizedTargets = targets.map(CourseCode.normalize).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        for target in normalizedTargets {
            state.currentTarget = target
            roots.append(node(target, kind: nil, alternatives: [], groupKey: nil, isTarget: true, choices: choices, state: &state))
        }
        return ChainPlan(targets: normalizedTargets, roots: roots, additions: state.order.compactMap { state.additions[$0] },
                         choices: state.choices, warnings: state.warnings)
    }

    private struct Walk {
        var additions: [String: ChainAddition] = [:]
        var order: [String] = []
        var visiting: [String] = []
        var choices: [ChainChoice] = []
        var warnings: [String] = []
        var currentTarget = ""

        mutating func warn(_ text: String) { if !warnings.contains(text) { warnings.append(text) } }
    }

    private func node(_ code: String, kind: RequirementKind?, alternatives: [String], groupKey: String?, isTarget: Bool,
                      choices: [String: String], state: inout Walk) -> ChainNode {
        let catalog = dataset.course(code)
        let title = catalog?.title ?? plan.find(code)?.title ?? ""
        let credits = plan.find(code)?.credits ?? catalog?.credits ?? 3
        func make(_ s: ChainNode.State, _ children: [ChainNode] = [], code display: String = code) -> ChainNode {
            ChainNode(id: "\(groupKey ?? "root")>\(display)", code: display, title: title, credits: credits, kind: kind, state: s,
                      alternatives: alternatives, groupKey: groupKey, children: children)
        }
        if let existing = plan.find(code) {
            return make(.inPlan(code: existing.code, term: existing.term), code: existing.code)
        }
        if state.additions[code] != nil {
            if !state.additions[code]!.requiredFor.contains(state.currentTarget) { state.additions[code]!.requiredFor.append(state.currentTarget) }
            return make(.addedAbove)
        }
        if state.visiting.contains(code) {
            // A lecture ↔ lab corequisite loop is normal: the class is being added already.
            if kind == .coreq { return make(.addedAbove) }
            state.warn("Requirement cycle: \((state.visiting.drop { $0 != code } + [code]).joined(separator: " → ")).")
            return make(.cycle)
        }
        let summary = offered?(code)
        guard let catalog else {
            state.warn("\(code) isn’t in the bundled \(dataset.program.catalogYear) catalog — check its prerequisites with the department.")
            state.additions[code] = ChainAddition(code: code, title: "", credits: 3, prereqs: [], coreqs: [], summerOk: summary?.summer ?? false,
                                                  isTarget: isTarget, requiredFor: [state.currentTarget], notes: [], inCatalog: false)
            state.order.append(code)
            return make(.unknown)
        }
        if let summary, summary.known, !summary.isOffered {
            state.warn("\(code) hasn’t been offered in the last two years and isn’t on an upcoming schedule.")
        }
        state.visiting.append(code)
        var children: [ChainNode] = []
        var prereqs: [String] = []
        var coreqs: [String] = []
        let groups = catalog.prereqGroups.enumerated().map { (RequirementKind.prereq, $0.offset, $0.element) }
            + catalog.sameTermGroups.enumerated().map { (RequirementKind.coreq, $0.offset, $0.element) }
        for (groupKind, index, rawGroup) in groups {
            let group = rawGroup.map(CourseCode.normalize)
            guard !group.isEmpty else { continue }
            let key = Self.groupKey(owner: code, kind: groupKind, index: index)
            let alts = group.count > 1 ? group : []
            let picked: String
            if let inPlan = group.first(where: { plan.contains($0) }) {
                picked = inPlan
            } else if let adding = group.first(where: { state.additions[$0] != nil }) {
                picked = adding
            } else {
                let wanted = choices[key].map(CourseCode.normalize)
                picked = (wanted.flatMap { w in group.contains(w) ? w : nil }) ?? best(group)
                if group.count > 1 {
                    var costs: [String: Int] = [:]
                    for option in group { costs[option] = cost(option) }
                    state.choices.append(ChainChoice(key: key, owner: code, kind: groupKind, options: group, chosen: picked, costs: costs))
                }
            }
            let child = node(picked, kind: groupKind, alternatives: alts, groupKey: key, isTarget: false, choices: choices, state: &state)
            children.append(child)
            let refCode: String
            if case .inPlan(let planCode, _) = child.state { refCode = planCode } else { refCode = picked }
            if groupKind == .prereq { prereqs.append(refCode) } else { coreqs.append(refCode) }
        }
        state.visiting.removeLast()
        if state.additions[code] == nil {
            state.additions[code] = ChainAddition(code: code, title: catalog.title, credits: catalog.credits ?? 3, prereqs: prereqs, coreqs: coreqs,
                                                  summerOk: summary?.summer ?? false, isTarget: isTarget,
                                                  requiredFor: [state.currentTarget], notes: catalog.notes, inCatalog: true)
            state.order.append(code)
        }
        return make(.add, children)
    }
}
