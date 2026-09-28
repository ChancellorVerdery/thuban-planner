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
    /// Values are passed through untouched; `PlannerData(json:)` then normalizes them like `loadCourse()`.
    public var recomposed: JSONValue {
        let courses = self.courses.map { row -> JSONValue in
            guard case .object(let r) = row else { return row }
            var o: [String: JSONValue] = [:]
            for (from, to) in [("id", "id"), ("code", "code"), ("title", "title"), ("credits", "credits"), ("prereqs", "prereqs"),
                               ("coreqs", "coreqs"), ("pre_or_co", "preOrCo"), ("summer_ok", "summerOk"), ("term_key", "term")] {
                if let v = r[from] { o[to] = v }
            }
            return .object(o)
        }
        let terms = self.terms.map { row -> JSONValue in
            guard case .object(let r) = row else { return row }
            var o: [String: JSONValue] = [:]
            for key in ["key", "season", "year", "current"] { if let v = r[key] { o[key] = v } }
            return .object(o)
        }
        var blob: [String: JSONValue] = ["courses": .array(courses), "terms": .array(terms)]
        if case .object(let g)? = settings {
            var s: [String: JSONValue] = [:]
            if let v = g["max_credits"] { s["maxCredits"] = AtlasDocument.unwrapJSONText(v) }
            if let v = g["summer_max"] { s["summerMax"] = AtlasDocument.unwrapJSONText(v) }
            if let v = g["strategy"] { s["strategy"] = v }
            blob["settings"] = .object(s)
            if let v = g["disabled_terms"] { blob["disabledTerms"] = v }
        }
        return .object(blob)
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
