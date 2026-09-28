import Foundation

/// The single JSON document the Atlas import SQL returns (see `AtlasImporter.sql(email:)`), or that a user saved to
/// a file: the account's `course.settings` row and its `course.terms` / `course.courses` rows in `ord` order,
/// without `user_id`. Every column is kept as raw JSON (`JSONValue`) — jsonb settings may be numbers OR numeric
/// strings, numerics may arrive as strings, text[] as arrays — and only `AtlasImporter.convert` interprets them,
/// through the same normalization Atlas's loader applies. Unknown keys are ignored.
public struct AtlasDocument: Decodable, Sendable, Equatable {
    public static let format = "thuban.atlas-course.v1"

    public var format: String?
    /// The account the rows belong to (echoed back by the SQL).
    public var email: String?
    public var userFound: Bool
    public var exportedAt: String?
    /// `{max_credits, summer_max, strategy, disabled_terms}` or nil when the account never opened the planner.
    public var settings: JSONValue?
    /// `{key, season, year, current}` rows.
    public var terms: [JSONValue]
    /// `{id, code, title, credits, prereqs, coreqs, summer_ok, term_key}` rows.
    public var courses: [JSONValue]

    enum CodingKeys: String, CodingKey { case format, email, userFound = "user_found", exportedAt = "exported_at", settings, terms, courses }

    public init(format: String? = AtlasDocument.format, email: String? = nil, userFound: Bool = true, exportedAt: String? = nil,
                settings: JSONValue? = nil, terms: [JSONValue] = [], courses: [JSONValue] = []) {
        self.format = format
        self.email = email
        self.userFound = userFound
        self.exportedAt = exportedAt
        self.settings = settings
        self.terms = terms
        self.courses = courses
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try? c.decodeIfPresent(String.self, forKey: .format)
        email = try? c.decodeIfPresent(String.self, forKey: .email)
        userFound = JS.truthy((try? c.decodeIfPresent(JSONValue.self, forKey: .userFound)) ?? .bool(true))
        exportedAt = try? c.decodeIfPresent(String.self, forKey: .exportedAt)
        // `settings` is one row; accept an array of rows too (first wins).
        let rawSettings = try? c.decodeIfPresent(JSONValue.self, forKey: .settings)
        switch rawSettings {
        case .object?: settings = rawSettings
        case .array(let rows)?: settings = rows.first { $0.isObject }
        default: settings = nil
        }
        terms = ((try? c.decodeIfPresent(JSONValue.self, forKey: .terms))??.arrayValue) ?? []
        courses = ((try? c.decodeIfPresent(JSONValue.self, forKey: .courses))??.arrayValue) ?? []
    }

    /// The rows turned back into Atlas's `atlas.course.v1` blob — the backend mapper's `recompose(rows)`:
    /// `summer_ok` → `summerOk`, `term_key` → `term`, settings columns → camelCase, `disabled_terms` → `disabledTerms`.
    /// Values are passed through untouched — except Postgres TEXT forms, which a file exported with plain psql (not the
    /// import SQL, whose `json_build_object` always yields native JSON) may carry: a `text[]` rendered as `{a,"b c"}`
    /// becomes a JSON array and a boolean rendered as `t` / `f` becomes a JSON boolean (`postgresArray`,
    /// `postgresBool`). `PlannerData(json:)` then normalizes them like `loadCourse()` (whose JS coercions would
    /// otherwise read `"f"` as true and drop `"{a,b}"`).
    public var recomposed: JSONValue {
        let courses = self.courses.map { row -> JSONValue in
            guard case .object(let r) = row else { return row }
            var o: [String: JSONValue] = [:]
            for (from, to) in [("id", "id"), ("code", "code"), ("title", "title"), ("credits", "credits"), ("prereqs", "prereqs"),
                               ("coreqs", "coreqs"), ("pre_or_co", "preOrCo"), ("summer_ok", "summerOk"), ("term_key", "term")] {
                guard let v = r[from] else { continue }
                switch from {
                case "prereqs", "coreqs", "pre_or_co": o[to] = AtlasDocument.postgresArray(v)
                case "summer_ok": o[to] = AtlasDocument.postgresBool(v)
                default: o[to] = v
                }
            }
            return .object(o)
        }
        let terms = self.terms.map { row -> JSONValue in
            guard case .object(let r) = row else { return row }
            var o: [String: JSONValue] = [:]
            for key in ["key", "season", "year"] { if let v = r[key] { o[key] = v } }
            if let v = r["current"] { o["current"] = AtlasDocument.postgresBool(v) }
            return .object(o)
        }
        var blob: [String: JSONValue] = ["courses": .array(courses), "terms": .array(terms)]
        if case .object(let g)? = settings {
            var s: [String: JSONValue] = [:]
            if let v = g["max_credits"] { s["maxCredits"] = AtlasDocument.unwrapJSONText(v) }
            if let v = g["summer_max"] { s["summerMax"] = AtlasDocument.unwrapJSONText(v) }
            if let v = g["strategy"] { s["strategy"] = v }
            blob["settings"] = .object(s)
            if let v = g["disabled_terms"] { blob["disabledTerms"] = AtlasDocument.postgresArray(v) }
        }
        return .object(blob)
    }

    /// A Postgres array literal (`{}`, `{A,B}`, `{"MATH 1241",NULL,"say \"hi\""}`) as a JSON array of strings (an
    /// unquoted NULL element becomes JSON null). Anything else — a real JSON array, null, a string that is not a
    /// literal — is returned unchanged. Nested literals become nested arrays.
    public static func postgresArray(_ value: JSONValue) -> JSONValue {
        guard case .string(let text) = value else { return value }
        let scalars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)
        guard scalars.first == "{", scalars.last == "}" else { return value }
        var index = 0
        guard let parsed = parsePostgresArray(scalars, &index), index == scalars.count else { return value }
        return parsed
    }

    /// `{ elem, elem, … }` starting at `scalars[index] == "{"`; advances `index` past the closing brace. nil = malformed.
    private static func parsePostgresArray(_ s: [Unicode.Scalar], _ index: inout Int) -> JSONValue? {
        guard index < s.count, s[index] == "{" else { return nil }
        index += 1
        var items: [JSONValue] = []
        func skipSpace() { while index < s.count, s[index].properties.isWhitespace { index += 1 } }
        skipSpace()
        if index < s.count, s[index] == "}" { index += 1; return .array(items) }
        while index < s.count {
            skipSpace()
            guard index < s.count else { return nil }
            if s[index] == "{" {
                guard let nested = parsePostgresArray(s, &index) else { return nil }
                items.append(nested)
            } else if s[index] == "\"" {
                index += 1
                var text = String.UnicodeScalarView()
                var closed = false
                while index < s.count {
                    let c = s[index]
                    index += 1
                    if c == "\\" {
                        guard index < s.count else { return nil }
                        text.append(s[index]); index += 1
                    } else if c == "\"" {
                        closed = true; break
                    } else {
                        text.append(c)
                    }
                }
                guard closed else { return nil }
                items.append(.string(String(text)))
            } else {
                var text = String.UnicodeScalarView()
                while index < s.count, s[index] != ",", s[index] != "}" {
                    if s[index] == "\\" {
                        index += 1
                        guard index < s.count else { return nil }
                    }
                    text.append(s[index]); index += 1
                }
                let element = String(text).trimmingCharacters(in: .whitespaces)
                items.append(element.uppercased() == "NULL" ? .null : .string(element))
            }
            skipSpace()
            guard index < s.count else { return nil }
            if s[index] == "," { index += 1; continue }
            if s[index] == "}" { index += 1; return .array(items) }
            return nil
        }
        return nil
    }

    /// A Postgres boolean in text form (`t` / `f`, as psql prints it; also `true` / `false`) as a JSON boolean.
    /// Anything else is returned unchanged.
    public static func postgresBool(_ value: JSONValue) -> JSONValue {
        guard case .string(let text) = value else { return value }
        switch text.trimmingCharacters(in: .whitespaces).lowercased() {
        case "t", "true": return .bool(true)
        case "f", "false": return .bool(false)
        default: return value
        }
    }

    /// jsonb arrives parsed (`18` or `"18"`); a client that stored JSON text in it (`"\"18\""`) is unwrapped once.
    static func unwrapJSONText(_ value: JSONValue) -> JSONValue {
        guard case .string(let text) = value, text.hasPrefix("\""), let data = text.data(using: .utf8),
              let inner = try? JSONValue.parse(data) else { return value }
        return inner
    }

    /// Decodes psql output or a saved file: the first line that parses as a JSON object wins (psql may print notices
    /// around it).
    public static func decode(_ data: Data) throws -> AtlasDocument {
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(AtlasDocument.self, from: data) { return document }
        let text = String(decoding: data, as: UTF8.self)
        var lastError: Error?
        for line in text.split(whereSeparator: \.isNewline) where line.first == "{" {
            do {
                return try decoder.decode(AtlasDocument.self, from: Data(line.utf8))
            } catch {
                lastError = error
            }
        }
        if let lastError { throw ThubanError.decoding("The Atlas document could not be read: \(lastError.localizedDescription)") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ThubanError.decoding(trimmed.isEmpty ? "Atlas returned nothing." : "Atlas did not return a JSON document.")
    }
}
