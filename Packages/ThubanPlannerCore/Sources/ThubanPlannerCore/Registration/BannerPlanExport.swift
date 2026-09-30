import Foundation

/// One section the export adds to the new Plan Ahead plan (section-level item: term + CRN).
public struct BannerPlanExportItem: Hashable, Sendable, Identifiable {
    public var term: String
    public var crn: String
    public var subject: String
    public var courseNumber: String
    /// Section number, e.g. "001".
    public var section: String
    public var title: String
    public var credits: Double?
    /// "MWF 9:05–9:55 AM" (several meetings joined with "; "), or "No set time".
    public var times: String

    public var id: String { crn }
    /// "MEGR 2144".
    public var courseCode: String { "\(subject) \(courseNumber)" }

    public init(term: String, crn: String, subject: String, courseNumber: String, section: String, title: String,
                credits: Double?, times: String) {
        self.term = term
        self.crn = crn
        self.subject = subject
        self.courseNumber = courseNumber
        self.section = section
        self.title = title
        self.credits = credits
        self.times = times
    }

    public init(section s: BannerSection) {
        let timed = s.meetings.filter(\.isTimed)
        let times = timed.isEmpty ? (s.meetings.first?.summary ?? "No set time") : timed.map(\.summary).joined(separator: "; ")
        self.init(term: s.term, crn: s.crn, subject: s.subject, courseNumber: s.courseNumber, section: s.sequenceNumber,
                  title: s.title, credits: s.credits, times: times)
    }
}

/// A request the exporter sends inside the signed-in web session (built and guarded in Swift, sent by `fetch`).
public struct BannerExportRequest: Hashable, Sendable {
    public var method: String
    public var url: URL
    public var contentType: String
    public var body: Data

    public init(method: String, url: URL, contentType: String, body: Data) {
        self.method = method
        self.url = url
        self.contentType = contentType
        self.body = body
    }

    public var bodyText: String { String(decoding: body, as: UTF8.self) }

    /// One line for the log / dry run: "POST https://… [application/json] {…}".
    public var logLine: String { "\(method) \(url.absoluteString) [\(contentType)] \(bodyText)" }
}

/// What the export found on the plan pages before writing anything.
public struct BannerPlanPageInfo: Hashable, Sendable {
    public var planCount: Int?
    public var maxPlans: Int?
    /// `selectedPlan.planHeader.sequenceNumber` — nil on a new (unsaved, "pnew") plan page.
    public var selectedSequence: Int?
    public var selectedCourseCount: Int
    public var plans: [BannerPlan]

    public init(planCount: Int?, maxPlans: Int?, selectedSequence: Int?, selectedCourseCount: Int, plans: [BannerPlan]) {
        self.planCount = planCount
        self.maxPlans = maxPlans
        self.selectedSequence = selectedSequence
        self.selectedCourseCount = selectedCourseCount
        self.plans = plans
    }

    /// True when Banner won't take another plan (Plan Ahead disables "Create a New Plan" when planCount >= maxPlans).
    public var isFull: Bool {
        guard let maxPlans, maxPlans > 0 else { return false }
        return (planCount ?? plans.count) >= maxPlans
    }

    /// A page showing a new, empty plan (the only kind the export ever writes to).
    public var isNewEmptyPlan: Bool { selectedSequence == nil && selectedCourseCount == 0 }

    /// Reads `JSON.stringify(window.bootstraps)` from a plan page.
    public static func parse(bootstrapsJSON data: Data) throws -> BannerPlanPageInfo {
        let root: JSONValue
        do { root = try JSONValue.parse(data) } catch { throw ThubanError.decoding("The plan page data was not JSON.") }
        let header = root["selectedPlan"]?["planHeader"]
        let seq = header?["sequenceNumber"]?.bannerInt
        return BannerPlanPageInfo(planCount: root["planCount"]?.bannerInt, maxPlans: root["maxPlans"]?.bannerInt,
                                  selectedSequence: (seq ?? 0) > 0 ? seq : nil,
                                  selectedCourseCount: header?["planCourses"]?.arrayValue?.count ?? 0,
                                  plans: BannerPlanParser.plans(from: .object(["plans": root["plans"] ?? .array([])])))
    }
}

/// Outcome of one addPlanItem call.
public enum BannerAddPlanItemResult: Equatable, Sendable {
    case added(JSONValue)
    case rejected(String)
}

/// Outcome of the submitPlan/batch call.
public enum BannerSubmitPlanResult: Equatable, Sendable {
    case saved(sequenceNumber: Int?, description: String?)
    case rejected(String)
}

/// Builds and reads the requests of "Export to Banner…" — creating a NEW Plan Ahead plan from a timetable.
/// Request shapes come from UNC Charlotte's own JS (planView-mf.js: addPlanItem `{term, courseReferenceNumber,
/// section:"section"}` form POST; bannerWeb-mf.js: `Collection.save` batch → `<save endpoint>/batch`, JSON
/// `{create, update, destroy}`) and lwgw/UCR-Course-Scheduler term_plan.py (a working Banner 9 client).
public enum BannerPlanExport {
    public static let addPlanItemURL = URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/plan/addPlanItem")!
    public static let submitPlanBatchURL = URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/plan/submitPlan/batch")!
    /// Plan Ahead's term page ("Open Plan Ahead").
    public static let planAheadURL = URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/term/termSelection?mode=plan")!
    public static let termSearchURL = URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/term/search?mode=plan")!
    public static let selectPlanURL = URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/plan/selectPlan")!
    public static let newPlanURL = URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/plan/plan")!

    /// Banner's plan-name limit was not found in any source; the live page's `#txt_planDesc` maxlength wins when it
    /// has one. This fallback is a guess.
    public static let fallbackNameLimit = 60
    /// UNC Charlotte: "Students can have up to five (5) Self Service Banner plans each term."
    public static let documentedMaxPlans = 5

    /// The env flag: build and log the exact requests, send nothing.
    public static let dryRunEnvironmentKey = "THUBAN_PLANNER_EXPORT_DRY_RUN"

    public static func isDryRun(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[dryRunEnvironmentKey] == "1"
    }

    /// The timetable's sections as plan items (every section of a linked set; one item per CRN, in order).
    public static func items(for option: TimetableOption) -> [BannerPlanExportItem] {
        var seen = Set<String>()
        return option.sections.compactMap { s in seen.insert(s.crn).inserted ? BannerPlanExportItem(section: s) : nil }
    }

    /// Credits once per course (a linked lab would double count).
    public static func totalCredits(_ option: TimetableOption) -> Double {
        option.picks.reduce(0.0) { $0 + ($1.choice.sections.first?.credits ?? 0) }
    }

    /// "Thuban · Spring 2027 · Schedule 3".
    public static func defaultName(termLabel: String, scheduleNumber: Int) -> String {
        "Thuban · \(termLabel) · Schedule \(scheduleNumber)"
    }

    /// The name as sent: whitespace collapsed and trimmed.
    public static func cleanName(_ name: String) -> String { BannerText.collapse(name) }

    /// nil when fine; otherwise why the name can't be used.
    public static func nameProblem(_ name: String, limit: Int = fallbackNameLimit) -> String? {
        let clean = cleanName(name)
        if clean.isEmpty { return "Give the plan a name." }
        if clean.count > limit { return "Banner takes at most \(limit) characters (this is \(clean.count))." }
        return nil
    }

    // MARK: Requests

    /// `plan/addPlanItem` for one section, exactly as the page sends it (jQuery form encoding).
    public static func addPlanItemRequest(term: String, crn: String) -> BannerExportRequest {
        let body = formEncode([("term", term), ("courseReferenceNumber", crn), ("section", "section")])
        return BannerExportRequest(method: "POST", url: addPlanItemURL,
                                   contentType: "application/x-www-form-urlencoded; charset=UTF-8", body: Data(body.utf8))
    }

    /// `plan/submitPlan/batch` creating a NEW plan: every added model carries the plan name (`headerDescription`)
    /// and `headerComment` (null), as the page does for a "pnew" plan. `update` and `destroy` are always empty.
    public static func submitPlanRequest(models: [JSONValue], name: String) -> BannerExportRequest {
        let clean = cleanName(name)
        let create: [JSONValue] = models.map { model in
            guard case .object(var o) = model else { return model }
            o["headerDescription"] = .string(clean)
            o["headerComment"] = .null
            o["messages"] = nil
            return .object(o)
        }
        let root = JSONValue.object(["create": .array(create), "update": .array([]), "destroy": .array([])])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body = (try? encoder.encode(root)) ?? Data("{}".utf8)
        return BannerExportRequest(method: "POST", url: submitPlanBatchURL, contentType: "application/json", body: body)
    }

    /// The model a dry run pretends addPlanItem returned (the real one is Banner's plan-item model).
    public static func dryRunModel(for item: BannerPlanExportItem) -> JSONValue {
        .object(["term": .string(item.term), "courseReferenceNumber": .string(item.crn), "subject": .string(item.subject),
                 "courseNumber": .string(item.courseNumber), "section": .string(item.section), "courseTitle": .string(item.title),
                 "creditHours": item.credits.map { .number($0) } ?? .null])
    }

    /// Every write request an export of `items` would send, with dry-run models (for the log and tests).
    public static func plannedRequests(items: [BannerPlanExportItem], name: String) -> [BannerExportRequest] {
        items.map { addPlanItemRequest(term: $0.term, crn: $0.crn) } + [submitPlanRequest(models: items.map(dryRunModel), name: name)]
    }

    // MARK: Responses

    /// `{success:true, model:{…}}` → added; `{success:false, message}` → rejected with Banner's words.
    public static func parseAddPlanItem(_ data: Data, crn: String) -> BannerAddPlanItemResult {
        guard let root = try? JSONValue.parse(data), root.isObject else {
            return .rejected(BannerPage.looksLikeHTML(data) ? "Banner sent a web page instead of an answer — your sign-in may have ended."
                                                             : "Banner’s answer for CRN \(crn) couldn’t be read.")
        }
        if root["success"]?.bannerBool == true, let model = root["model"], model.isObject { return .added(model) }
        let message = messageText(root["message"]) ?? messageText(root["model"]?["messages"]) ?? "Banner didn’t add CRN \(crn)."
        return .rejected("CRN \(crn): \(message)")
    }

    /// Batch answer: `{success:true, data:{planHeader:{sequenceNumber, description}, create:[{…, messages:[{type}]}]}}`
    /// or `{success:false, message:[{message, type}]}`. A created item whose first message is an error fails it too.
    public static func parseSubmitPlan(_ data: Data) -> BannerSubmitPlanResult {
        guard let root = try? JSONValue.parse(data), root.isObject else {
            return .rejected(BannerPage.looksLikeHTML(data) ? "Banner sent a web page instead of an answer — your sign-in may have ended."
                                                             : "Banner’s answer to saving the plan couldn’t be read.")
        }
        if root["success"]?.bannerBool == false {
            return .rejected(messageText(root["message"]) ?? "Banner didn’t save the plan.")
        }
        for item in root["data"]?["create"]?.arrayValue ?? [] {
            if let first = item["messages"]?.arrayValue?.first, first["type"]?.bannerString?.lowercased() == "error" {
                return .rejected(messageText(item["messages"]) ?? "Banner refused a class in the plan.")
            }
        }
        let header = root["data"]?["planHeader"]
        return .saved(sequenceNumber: header?["sequenceNumber"]?.bannerInt, description: header?["description"]?.bannerString)
    }

    /// A message as text: a string, `{message}`, or an array of either (joined).
    static func messageText(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let s = value.bannerString, !s.isEmpty, value.stringValue != nil { return BannerText.collapse(s) }
        if value.isObject { return messageText(value["message"]) }
        if let list = value.arrayValue {
            let parts = list.compactMap { messageText($0) }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
        return nil
    }

    // MARK: Verification

    public enum Verification: Equatable, Sendable {
        case verified(BannerPlan)
        /// The plan is there but its sections differ.
        case mismatch(BannerPlan, missing: [String], extra: [String])
        case notFound
    }

    /// Finds the new plan in `plans` (by sequence number from the save answer, else by name) and compares its CRNs.
    public static func verify(plans: [BannerPlan], name: String, sequenceNumber: Int?, term: String, crns: [String],
                              previousSequences: Set<Int>) -> Verification {
        let clean = cleanName(name)
        let candidates = plans.filter { !previousSequences.contains($0.sequenceNumber) }
        let plan = sequenceNumber.flatMap { seq in plans.first { $0.sequenceNumber == seq } }
            ?? candidates.first { cleanName($0.description) == clean }
            ?? plans.first { cleanName($0.description) == clean }
        guard let plan else { return .notFound }
        let found = Set(plan.courses.filter { $0.term.isEmpty || $0.term == term }.compactMap(\.crn))
        let wanted = Set(crns)
        let missing = crns.filter { !found.contains($0) }
        let extra = found.subtracting(wanted).sorted()
        return missing.isEmpty && extra.isEmpty ? .verified(plan) : .mismatch(plan, missing: missing, extra: extra)
    }

    // MARK: Form encoding

    static func formEncode(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return pairs.map { key, value in
            let v = (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
            return "\(key)=\(v)"
        }.joined(separator: "&")
    }

    /// Parses an `application/x-www-form-urlencoded` body (for the guard). "+" means space.
    public static func parseForm(_ data: Data) -> [String: String] {
        var out: [String: String] = [:]
        for pair in String(decoding: data, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            func decode(_ s: String) -> String { s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s }
            guard let key = parts.first.map(decode), !key.isEmpty else { continue }
            out[key] = parts.count > 1 ? decode(parts[1]) : ""
        }
        return out
    }
}
