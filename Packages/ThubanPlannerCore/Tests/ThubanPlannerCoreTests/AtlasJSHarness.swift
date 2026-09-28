import Foundation
import JavaScriptCore
@testable import ThubanPlannerCore

/// Atlas's OWN JavaScript, running in-process under JavaScriptCore, as the reference for the differential parity
/// tests (`DifferentialParityTests`). Nothing here is a port: the fixtures are byte-for-byte copies of
///
/// - `Fixtures/atlas-course.js`         = atlas-ui/src/page/course.js (loadCourse, scheduleDegree, term helpers)
/// - `Fixtures/atlas-course-backend.js` = atlas-backend/services/plugins/course.js (decompose / recompose)
/// - `Fixtures/v8sort.js`               = tools/golden/v8sort.js (V8's TimSort, see below)
///
/// and the only edits are mechanical, made at load time: the ES `export` keywords are stripped (JSContext runs
/// classic scripts, not modules; the course file then runs under `'use strict'` like a module would), the backend's
/// `import` / `export default` / `import.meta` lines are dropped and its body is wrapped in a function so its private
/// helpers do not collide with the UI file's, and `localStorage` is a one-slot in-memory stub.
/// `upcomingSummers` / `planStatus` are copied verbatim from atlas-ui/src/page/courseui.js (they are not exported
/// there) with `now` passed in instead of read from the clock.
///
/// Sorting: Atlas runs in Chrome / Electron (V8), whose `Array.prototype.sort` is TimSort; JavaScriptCore's is a
/// merge sort. For a consistent comparator the results are identical (both are stable), but `scheduleDegree`'s class
/// comparator memoizes "depth" lazily, so inside a requirement cycle the result depends on the comparator CALL
/// ORDER. `run(v8Sort: true)` installs the V8 TimSort port; `run(v8Sort: false)` keeps JavaScriptCore's native sort
/// and is used as an independent check wherever the call order cannot matter (acyclic plans).
final class AtlasJS {
    let context: JSContext
    private var exception: String?

    struct LoadError: Error, CustomStringConvertible { var description: String }

    init() throws {
        guard let context = JSContext() else { throw LoadError(description: "JSContext unavailable") }
        self.context = context
        context.exceptionHandler = { [weak self] _, value in self?.exception = value?.toString() ?? "unknown JS exception" }

        try evaluate(Self.prelude, name: "prelude")
        let course = try String(contentsOf: TestSupport.fixtureURL("atlas-course.js"), encoding: .utf8)
        try evaluate("'use strict';\n" + Self.stripExports(course), name: "atlas-course.js")
        let v8sort = try String(contentsOf: TestSupport.fixtureURL("v8sort.js"), encoding: .utf8)
        try evaluate(Self.stripExports(v8sort), name: "v8sort.js")
        let backend = try String(contentsOf: TestSupport.fixtureURL("atlas-course-backend.js"), encoding: .utf8)
        try evaluate(Self.wrapBackend(backend), name: "atlas-course-backend.js")
        try evaluate(Self.harness, name: "harness")
    }

    private func evaluate(_ source: String, name: String) throws {
        exception = nil
        context.evaluateScript(source, withSourceURL: URL(string: "atlas://\(name)"))
        if let exception { throw LoadError(description: "\(name): \(exception)") }
    }

    /// `export function f` → `function f`, `export const x` → `const x`, `export { a }` → removed.
    static func stripExports(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            if line.hasPrefix("export {") { return "" }
            if line.hasPrefix("export ") { return String(line.dropFirst("export ".count)) }
            return String(line)
        }.joined(separator: "\n")
    }

    /// The backend module body inside `const __mapper = (() => { 'use strict'; …; return mapper })()`.
    static func wrapBackend(_ source: String) -> String {
        let body = source.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            !(line.hasPrefix("import ") || line.hasPrefix("export default") || line.hasPrefix("if (import.meta"))
        }.joined(separator: "\n")
        return "const __mapper = (() => {\n'use strict';\n\(body)\nreturn mapper\n})()\n"
    }

    /// Runs one raw document through Atlas: backend `decompose` → Postgres (jsonb settings come back parsed, the
    /// `text` id column holds a string) → `recompose` → the UI's `loadCourse()` → `scheduleDegree(s, new Date(now))`
    /// plus the Planner page's `upcomingSummers` / `planStatus`. Returns the JSON text of
    /// `{ normalized, schedule, summers, status }` or `{ error }`.
    func run(raw: String, nowMs: Double, v8Sort: Bool) -> String {
        exception = nil
        let result = context.objectForKeyedSubscript("__run")?.call(withArguments: [raw, nowMs, v8Sort])
        if let exception { return #"{"error":"harness: \#(exception)"}"# }
        return result?.toString() ?? #"{"error":"no result"}"#
    }

    private static let prelude = #"""
    var __store = null
    var localStorage = { getItem(k) { return __store }, setItem(k, v) { __store = String(v) }, removeItem(k) { __store = null } }
    const __nativeSort = Array.prototype.sort
    """#

    private static let harness = #"""
    'use strict';
    const __v8Sort = Array.prototype.sort

    // atlas-ui/src/page/courseui.js, verbatim except `now` is a parameter (currentTermKey() → currentTermKey(now)).
    function upcomingSummers(s, now) {
      const start = s.terms.length ? s.terms[s.terms.length - 1].key : currentTermKey(now)
      const out = new Set(s.disabledTerms.filter((k) => parseTerm(k).season === 'summer'))
      let cur = start
      for (let i = 0; i < 15; i++) { cur = nextTermKey(cur); if (parseTerm(cur).season === 'summer') out.add(cur) }
      return [...out].sort((a, b) => termRank(a) - termRank(b)).slice(0, 5)
    }
    function planStatus(s, sched) {
      const remaining = s.courses.filter((c) => !c.term)
      const cr = remaining.reduce((t, c) => t + c.credits, 0)
      if (!remaining.length) return `${s.courses.length} classes · nothing left to schedule`
      const grad = sched.gradTerm && sched.termsToFinish ? ` · finishes ${termLabel(sched.gradTerm)}` : ''
      return `${remaining.length} to take · ${cr} credits · ${sched.termsToFinish} more term${sched.termsToFinish === 1 ? '' : 's'}${grad}`
    }

    function __run(raw, nowMs, v8) {
      Array.prototype.sort = v8 ? __v8Sort : __nativeSort
      try {
        // What the Atlas server stores and hands back (the Thuban importer reads the same rows).
        const rows = __mapper.decompose(JSON.parse(raw) || {})
        const g = rows.settings[0]
        g.max_credits = JSON.parse(g.max_credits)   // jsonb column
        g.summer_max = JSON.parse(g.summer_max)     // jsonb column
        for (const r of rows.courses) r.id = String(r.id) // text column
        localStorage.setItem('atlas.course.v1', JSON.stringify(__mapper.recompose(rows)))
        // What the Atlas UI then works with.
        const s = loadCourse()
        const now = new Date(nowMs)
        const schedule = scheduleDegree(s, now)
        return JSON.stringify({
          normalized: {
            courses: s.courses, terms: s.terms, disabledTerms: s.disabledTerms,
            // loadCourse keeps valid numeric strings ("18"); every consumer reads them through Number().
            settings: { maxCredits: Number(s.settings.maxCredits), summerMax: Number(s.settings.summerMax), strategy: s.settings.strategy },
          },
          schedule, summers: upcomingSummers(s, now), status: planStatus(s, schedule),
        })
      } catch (e) {
        return JSON.stringify({ error: String((e && e.stack) || e) })
      } finally {
        Array.prototype.sort = __v8Sort
      }
    }
    """#
}

/// A structural JSON diff: returns "path: a ≠ b" lines. A missing key equals `null` (Swift's synthesized Codable
/// omits nil optionals; JSON.stringify writes `null`). Numbers compare as Doubles (so -0 == 0, as JSON.stringify
/// prints -0 as 0).
enum JSONDiff {
    static func diff(_ a: JSONValue?, _ b: JSONValue?, path: String = "$", limit: Int = 12) -> [String] {
        var out: [String] = []
        walk(a ?? .null, b ?? .null, path, &out, limit)
        return out
    }

    private static func walk(_ a: JSONValue, _ b: JSONValue, _ path: String, _ out: inout [String], _ limit: Int) {
        guard out.count < limit else { return }
        switch (a, b) {
        case (.object(let x), .object(let y)):
            for key in Set(x.keys).union(y.keys).sorted() {
                walk(x[key] ?? .null, y[key] ?? .null, "\(path).\(key)", &out, limit)
            }
        case (.array(let x), .array(let y)):
            if x.count != y.count { out.append("\(path): count \(x.count) ≠ \(y.count) — \(short(a)) ≠ \(short(b))"); return }
            for (i, pair) in zip(x, y).enumerated() { walk(pair.0, pair.1, "\(path)[\(i)]", &out, limit) }
        case (.number(let x), .number(let y)):
            if x != y && !(x.isNaN && y.isNaN) { out.append("\(path): \(x) ≠ \(y)") }
        default:
            if a != b { out.append("\(path): \(short(a)) ≠ \(short(b))") }
        }
    }

    static func short(_ v: JSONValue) -> String {
        let data = (try? JSONEncoder().encode(v)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        return text.count > 240 ? String(text.prefix(240)) + "…" : text
    }
}
