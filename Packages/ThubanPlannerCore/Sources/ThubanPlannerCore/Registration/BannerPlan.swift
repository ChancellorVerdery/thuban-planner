import Foundation

/// A course in a Banner "Plan Ahead" plan. `crn == nil` means a course-level plan item (any section).
public struct BannerPlanCourse: Codable, Hashable, Sendable {
    public var term: String
    public var subject: String
    public var courseNumber: String
    public var title: String
    public var crn: String?
    public var section: String?
    public var credits: Double?
    public var isRegistered: Bool

    public init(term: String, subject: String, courseNumber: String, title: String = "", crn: String? = nil, section: String? = nil,
                credits: Double? = nil, isRegistered: Bool = false) {
        self.term = term
        self.subject = subject
        self.courseNumber = courseNumber
        self.title = title
        self.crn = crn
        self.section = section
        self.credits = credits
        self.isRegistered = isRegistered
    }

    /// "MEGR 2144".
    public var courseCode: String { "\(subject) \(courseNumber)" }
}

/// One of the student's Plan Ahead plans.
public struct BannerPlan: Codable, Hashable, Sendable, Identifiable {
    public var sequenceNumber: Int
    public var description: String
    public var preferred: Bool
    public var totalCredits: Double?
    public var courses: [BannerPlanCourse]

    public var id: Int { sequenceNumber }

    public init(sequenceNumber: Int, description: String, preferred: Bool = false, totalCredits: Double? = nil, courses: [BannerPlanCourse]) {
        self.sequenceNumber = sequenceNumber
        self.description = description
        self.preferred = preferred
        self.totalCredits = totalCredits
        self.courses = courses
    }

    /// "My Spring Plan", or "Plan 2" when unnamed.
    public var displayName: String { description.isEmpty ? "Plan \(sequenceNumber)" : description }

    /// The plan's courses in one term (a course without a term counts for every term), one entry per course code
    /// (the first item with a CRN wins over a course-level item).
    public func courses(inTerm code: String) -> [BannerPlanCourse] {
        var out: [BannerPlanCourse] = []
        for course in courses where course.term.isEmpty || course.term == code {
            if let index = out.firstIndex(where: { $0.courseCode == course.courseCode }) {
                if out[index].crn == nil, course.crn != nil { out[index] = course }
            } else {
                out.append(course)
            }
        }
        return out
    }
}

/// Reads `window.bootstraps` from Banner's plan page (`plan/selectPlan`), tolerant of missing / renamed / mistyped
/// fields. Source: `bootstraps.plans[]` and `bootstraps.selectedPlan.planHeader` (a single plan the page opened).
public enum BannerPlanParser {
    /// Plans from `JSON.stringify(window.bootstraps)` (the preferred plan first, then by sequence number).
    public static func parse(bootstrapsJSON data: Data) throws -> [BannerPlan] {
        let root: JSONValue
        do { root = try JSONValue.parse(data) } catch { throw ThubanError.decoding("The plan page data was not JSON.") }
        return plans(from: root)
    }

    /// Plans from the plan page's HTML: finds `window.bootstraps = {…}` and reads the object literal (JSON, or a
    /// simple JavaScript literal with bare keys / single quotes). Returns [] when there is no plan data.
    public static func parse(html: String) throws -> [BannerPlan] {
        guard let literal = extractBootstraps(html) else { return [] }
        if let data = literal.data(using: .utf8), let value = try? JSONValue.parse(data) { return plans(from: value) }
        let relaxed = relaxJavaScriptLiteral(literal)
        guard let data = relaxed.data(using: .utf8), let value = try? JSONValue.parse(data) else {
            throw ThubanError.decoding("The plan page's data could not be read.")
        }
        return plans(from: value)
    }

    static func plans(from root: JSONValue) -> [BannerPlan] {
        var result: [BannerPlan] = []
        for (index, raw) in (root["plans"]?.arrayValue ?? []).enumerated() {
            if let plan = plan(raw, fallbackSequence: index + 1) { result.append(plan) }
        }
        if let header = root["selectedPlan"]?["planHeader"], let plan = plan(header, fallbackSequence: result.count + 1) {
            if let index = result.firstIndex(where: { $0.sequenceNumber == plan.sequenceNumber }) {
                // The open plan's header may carry courses the list omitted.
                if result[index].courses.isEmpty { result[index].courses = plan.courses }
            } else if !plan.courses.isEmpty || result.isEmpty {
                result.append(plan)
            }
        }
        return result.sorted { a, b in
            if a.preferred != b.preferred { return a.preferred }
            return a.sequenceNumber < b.sequenceNumber
        }
    }

    static func plan(_ raw: JSONValue, fallbackSequence: Int) -> BannerPlan? {
        guard raw.isObject else { return nil }
        let courses = (raw["planCourses"]?.arrayValue ?? raw["courses"]?.arrayValue ?? []).compactMap(course)
        return BannerPlan(sequenceNumber: raw["sequenceNumber"]?.bannerInt ?? fallbackSequence,
                          description: BannerText.collapse(raw["description"]?.bannerString ?? ""),
                          preferred: raw["preferredIndicator"]?.bannerBool ?? false,
                          totalCredits: raw["totalPlannedCreditHours"]?.bannerDouble,
                          courses: courses)
    }

    static func course(_ raw: JSONValue) -> BannerPlanCourse? {
        guard raw.isObject else { return nil }
        var subject = raw["subject"]?.bannerString?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        var number = (raw["courseNumber"]?.bannerString ?? raw["courseDisplay"]?.bannerString ?? "")
            .trimmingCharacters(in: .whitespaces).uppercased()
        if subject.isEmpty || number.isEmpty, let split = raw["subjectCourse"]?.bannerString.flatMap(BannerText.splitCourseCode) {
            subject = split.subject
            number = split.number
        }
        guard !subject.isEmpty, !number.isEmpty else { return nil }
        let crn = raw["courseReferenceNumber"]?.bannerString.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let section = raw["section"]?.bannerString ?? raw["sequenceNumber"]?.bannerString
        return BannerPlanCourse(term: raw["term"]?.bannerString ?? "",
                                subject: subject, courseNumber: number,
                                title: BannerText.collapse(raw["courseTitle"]?.bannerString ?? raw["title"]?.bannerString ?? ""),
                                crn: crn,
                                section: section.flatMap { $0.isEmpty ? nil : $0 },
                                credits: raw["creditHours"]?.bannerDouble ?? raw["creditHourLow"]?.bannerDouble,
                                isRegistered: raw["isRegistered"]?.bannerBool ?? false)
    }

    /// The `{…}` after `window.bootstraps =` (or `bootstraps =`), brace-matched outside of strings.
    static func extractBootstraps(_ html: String) -> String? {
        guard let marker = html.range(of: #"(window\.)?bootstraps\s*=\s*\{"#, options: .regularExpression) else { return nil }
        let chars = Array(html[html.index(before: marker.upperBound)...])
        var depth = 0
        var quote: Character?
        var escaped = false
        for (i, c) in chars.enumerated() {
            if let q = quote {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == q { quote = nil }
                continue
            }
            switch c {
            case "\"", "'": quote = c
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(chars[0...i]) }
            default: break
            }
        }
        return nil
    }

    /// Quotes bare keys and turns single-quoted strings into JSON strings; drops trailing commas.
    static func relaxJavaScriptLiteral(_ js: String) -> String {
        var out = ""
        let chars = Array(js)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" || c == "'" {
                // Copy a string, re-quoting single-quoted ones.
                var j = i + 1
                var body = ""
                while j < chars.count, chars[j] != c {
                    if chars[j] == "\\", j + 1 < chars.count { body.append(chars[j]); body.append(chars[j + 1]); j += 2; continue }
                    if c == "'" && chars[j] == "\"" { body.append("\\\"") } else { body.append(chars[j]) }
                    j += 1
                }
                out += "\"\(body)\""
                i = j + 1
                continue
            }
            if c.isLetter || c == "_" || c == "$" {
                var j = i
                var word = ""
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "$" { word.append(chars[j]); j += 1 }
                var k = j
                while k < chars.count, chars[k].isWhitespace { k += 1 }
                if k < chars.count, chars[k] == ":", !["true", "false", "null"].contains(word) {
                    out += "\"\(word)\""
                } else if word == "undefined" {
                    out += "null"
                } else {
                    out += word
                }
                i = j
                continue
            }
            if c == "," {
                var k = i + 1
                while k < chars.count, chars[k].isWhitespace { k += 1 }
                if k < chars.count, chars[k] == "}" || chars[k] == "]" { i += 1; continue }
            }
            out.append(c)
            i += 1
        }
        return out
    }
}

/// Reads `<meta name="…" content="…">` values (the synchronizer token, the signed-in student's `fullName`).
public enum BannerPage {
    public static func meta(_ name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [#"<meta\s+name\s*=\s*["']"# + escaped + #"["']\s+content\s*=\s*["']([^"']*)["']"#,
                        #"<meta\s+content\s*=\s*["']([^"']*)["']\s+name\s*=\s*["']"# + escaped + #"["']"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            return String(html[range])
        }
        return nil
    }

    /// `{"fwdURL": "…"}` from a `term/search` POST.
    public static func forwardURL(_ data: Data) -> String? {
        guard let value = try? JSONValue.parse(data), let url = value["fwdURL"]?.bannerString, !url.isEmpty else { return nil }
        return url
    }

    /// True when a URL is a sign-in page (UNC Charlotte web auth / CAS) or Banner's own sign-in landing.
    public static func isSignInURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if host.contains("webauth") || host.hasPrefix("login.") || host.contains("shibboleth") || host.contains("microsoftonline") { return true }
        if path.contains("/login") || path.contains("/cas") || path.hasSuffix("/registration/registration") { return true }
        return false
    }

    /// True when a response body looks like HTML (a sign-in page where JSON was expected).
    public static func looksLikeHTML(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(512), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return head.hasPrefix("<!doctype") || head.hasPrefix("<html") || head.hasPrefix("<")
    }
}
