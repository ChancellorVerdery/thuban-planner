import Foundation

/// Thuban-only pass after Atlas's packing: a planned fall / spring term under `minCredits` takes classes from
/// EARLIER planned terms, moved later, while every rule still holds — the class's own requirements were already
/// met earlier, every class needing it as a prerequisite stays in a later term, every class needing it as a
/// corequisite stays in the same or a later term, the target stays within its cap, and the source term keeps at
/// least its own minimum. Terms are never added or removed, so the finish term never moves. Deterministic: targets
/// from the last term back, sources nearest first, the biggest class that fits first (then code).
enum MinimumBalancer {
    typealias Term = (key: String, ids: [String], credits: Double)

    static func balance(_ input: [Term], settings g: PlannerSettings, courses: [Course], keys: [JSKey],
                        byId: [JSKey: Int], preOf: (Int) -> [JSKey], coOf: (Int) -> [JSKey]) -> [Term] {
        var terms = input
        func isSummer(_ key: String) -> Bool { TermKey.parse(key).seasonText == "summer" }
        func credits(_ id: String) -> Double { byId[JSKey(id)].map { courses[$0].credits } ?? 0 }
        func code(_ id: String) -> String { byId[JSKey(id)].map { courses[$0].code } ?? id }
        func termIndex(of id: JSKey) -> Int? { terms.firstIndex { $0.ids.contains { JSKey($0) == id } } }

        // Who depends on each placed class, and how.
        var needsAsPre: [JSKey: [JSKey]] = [:], needsAsCo: [JSKey: [JSKey]] = [:]
        for t in terms {
            for id in t.ids {
                guard let i = byId[JSKey(id)] else { continue }
                for r in preOf(i) { needsAsPre[r, default: []].append(keys[i]) }
                for r in coOf(i) { needsAsCo[r, default: []].append(keys[i]) }
            }
        }

        let regularMin = g.effectiveMin(summer: false)
        for ti in terms.indices.reversed() where !isSummer(terms[ti].key) {
            while terms[ti].credits < regularMin {
                var moved = false
                for si in stride(from: ti - 1, through: 0, by: -1) {
                    let sourceMin = g.effectiveMin(summer: isSummer(terms[si].key))
                    let candidates = terms[si].ids.filter { id in
                        let key = JSKey(id)
                        let cr = credits(id)
                        guard cr > 0, terms[ti].credits + cr <= g.maxCredits else { return false }
                        let left = terms[si].credits - cr
                        guard left > 0, left >= sourceMin else { return false }
                        // Dependents: prereq users strictly after the target, coreq users at or after it.
                        for d in needsAsPre[key] ?? [] { if let di = termIndex(of: d), di <= ti { return false } }
                        for d in needsAsCo[key] ?? [] { if let di = termIndex(of: d), di < ti { return false } }
                        return true
                    }
                    let best = candidates.sorted { a, b in
                        let ca = credits(a), cb = credits(b)
                        return ca != cb ? ca > cb : code(a) < code(b)
                    }.first
                    if let id = best {
                        let cr = credits(id)
                        terms[si].ids.removeAll { $0 == id }
                        terms[si].credits -= cr
                        terms[ti].ids.append(id)
                        terms[ti].credits += cr
                        moved = true
                        break
                    }
                }
                if !moved { break }
            }
        }
        return terms
    }
}
