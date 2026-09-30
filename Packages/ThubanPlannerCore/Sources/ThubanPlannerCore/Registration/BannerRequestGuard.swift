import Foundation

/// The Schedule tab is READ-ONLY against Banner except for ONE user-confirmed action: "Export to Banner…", which
/// creates a NEW Plan Ahead plan. Rules:
///
/// - Registration is denied everywhere, always (`registrationFragments`): classRegistration/*, addRegistrationItem,
///   addCRNRegistrationItems, submitRegistration, "register", saveTerm.
/// - Plan writes other than creating a plan are denied everywhere, always (`planWriteFragments`): deletePlan,
///   makePreferred, savePlanNote, markApproved.
/// - The two plan-creation endpoints (`plan/addPlanItem`, `plan/submitPlan/batch`) are denied by default and allowed
///   ONLY for a request carrying a live `BannerExportAuthorization` — minted when the user clicks "Create plan" in the
///   export confirmation — whose term / CRNs / body match what the user confirmed (one addPlanItem per confirmed CRN,
///   one create-only batch).
///
/// Every request the app builds itself goes through `check(method:url:body:export:)`; every navigation inside the
/// web views goes through `checkBrowser(url:)`; WebKit content rules (`contentRuleListJSON` for the sign-in view,
/// `exportContentRuleListJSON` for the hidden export view) block the same fragments for every resource load.
public enum BannerRequestGuard {
    public enum Verdict: Equatable, Sendable {
        case allow
        case deny(String)

        public var isAllowed: Bool { self == .allow }
    }

    public static let host = "selfservice.uncc.edu"
    public static let basePath = "/StudentRegistrationSsb/"
    public static let base = URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb")!

    /// Registration writes: denied everywhere, always. "register" does not match "registration".
    public static let registrationFragments: [String] = [
        "classregistration/", "addregistrationitem", "addcrnregistrationitems", "submitregistration", "register", "saveterm",
    ]

    /// Plan writes the app never makes (changing / deleting existing plans): denied everywhere, always.
    public static let planWriteFragments: [String] = ["deleteplan", "makepreferred", "saveplannote", "markapproved"]

    /// The plan-creation endpoints: denied unless the request carries the user's export authorization.
    public static let exportFragments: [String] = ["addplanitem", "submitplan"]

    /// Every fragment that is denied without an export authorization.
    public static var deniedFragments: [String] { registrationFragments + planWriteFragments + exportFragments }

    /// The exact paths of the export's two writes (lower-cased, no trailing slash).
    public static let addPlanItemPath = "/studentregistrationssb/ssb/plan/addplanitem"
    public static let submitPlanBatchPath = "/studentregistrationssb/ssb/plan/submitplan/batch"

    /// The only read-only POST endpoints the app may call (selecting a term for the session; clearing the search form).
    public static let allowedPostPaths: [String] = [
        "/studentregistrationssb/ssb/term/search",
        "/studentregistrationssb/ssb/classsearch/resetdataform",
    ]

    /// The first of `fragments` a URL contains, if any (path and query, lower-cased; percent-decoded too).
    public static func fragment(in url: URL, from fragments: [String]) -> String? {
        let raw = url.absoluteString.lowercased()
        let decoded = (url.absoluteString.removingPercentEncoding ?? url.absoluteString).lowercased()
        let haystack = decoded.split(separator: "#", maxSplits: 1).first.map(String.init) ?? decoded
        return fragments.first { haystack.contains($0) || raw.contains($0) }
    }

    /// The denied fragment a URL contains, if any (without an export authorization).
    public static func deniedFragment(in url: URL) -> String? { fragment(in: url, from: deniedFragments) }

    private static func trimmedPath(_ url: URL) -> String {
        let path = url.path.lowercased()
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// For requests the app builds itself: HTTPS to selfservice.uncc.edu under /StudentRegistrationSsb/ only; any GET
    /// that is not a denied write; POST only to the read-only allowlist — or, with a live export authorization, to
    /// the two plan-creation endpoints with a body that matches what the user confirmed. Registration never.
    public static func check(method: String, url: URL, body: Data? = nil, export: BannerExportAuthorization? = nil) -> Verdict {
        if let fragment = fragment(in: url, from: registrationFragments) {
            return .deny("Blocked a request that could change your registration (\(fragment)).")
        }
        if let fragment = fragment(in: url, from: planWriteFragments) {
            return .deny("Blocked a request that could change an existing plan (\(fragment)).")
        }
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == host else {
            return .deny("Blocked a request outside Banner (\(url.host ?? url.absoluteString)).")
        }
        guard url.path.lowercased().hasPrefix(basePath.lowercased()) else { return .deny("Blocked a request outside Banner registration.") }
        if let fragment = fragment(in: url, from: exportFragments) {
            guard let export else {
                return .deny("Blocked a plan change that wasn’t confirmed in Export to Banner (\(fragment)).")
            }
            return export.authorize(method: method, url: url, body: body)
        }
        switch method.uppercased() {
        case "GET", "HEAD":
            return .allow
        case "POST":
            return allowedPostPaths.contains(trimmedPath(url)) ? .allow : .deny("Blocked a POST the Schedule tab never makes (\(url.path)).")
        default:
            return .deny("Blocked a \(method.uppercased()) request.")
        }
    }

    /// For navigations in the web views (the user's own sign-in, the export's page loads): everything is allowed
    /// EXCEPT the denied writes — the export's writes are fetches, never navigations.
    public static func checkBrowser(url: URL) -> Verdict {
        if let fragment = deniedFragment(in: url) { return .deny("Blocked a request that could change your registration or plan (\(fragment)).") }
        return .allow
    }

    /// WebKit content rules for the sign-in web view: block every denied fragment for all resource types, including
    /// fetch / XHR ("raw") and documents.
    public static var contentRuleListJSON: String { ruleList(deniedFragments) }

    /// Content rules for the hidden export web view: registration and existing-plan writes blocked; the two
    /// plan-creation endpoints are left to the exporter (guarded in Swift, and page scripts are fenced by
    /// `pageFenceScript`).
    public static var exportContentRuleListJSON: String { ruleList(registrationFragments + planWriteFragments) }

    private static func ruleList(_ fragments: [String]) -> String {
        let rules = fragments.map { fragment -> String in
            // Fragments are plain lower-case letters and "/", which WebKit's url-filter takes literally.
            let pattern = fragment.filter { $0.isLetter || $0 == "/" }
            return #"{"trigger":{"url-filter":".*"# + pattern + #".*","url-filter-is-case-sensitive":false},"action":{"type":"block"}}"#
        }
        return "[" + rules.joined(separator: ",") + "]"
    }

    /// Injected at document start into the export web view's PAGE world: Banner's own scripts cannot call any denied
    /// endpoint (fetch or XHR). The exporter's requests run in a separate content world with the unwrapped fetch.
    public static var pageFenceScript: String {
        let list = deniedFragments.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        (function(){
          var denied=[\(list)];
          function bad(u){try{var s=String(u).toLowerCase();var d=s;try{d=decodeURIComponent(s)}catch(e){}
            return denied.some(function(f){return s.indexOf(f)>=0||d.indexOf(f)>=0});}catch(e){return true}}
          var of=window.fetch;
          if(of){window.fetch=function(i,o){var u=(i&&i.url)?i.url:i;if(bad(u))return Promise.reject(new Error('Blocked by Thuban Planner'));return of.apply(this,arguments)};}
          var oo=XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open=function(m,u){this.__thubanBlocked=bad(u);return oo.apply(this,arguments)};
          var os=XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.send=function(){if(this.__thubanBlocked){throw new Error('Blocked by Thuban Planner')}return os.apply(this,arguments)};
        })();
        """
    }
}

/// The user's one-shot permission for ONE export: minted when they click "Create plan" in the export confirmation,
/// scoped to the term and the CRNs they saw. It allows exactly one `plan/addPlanItem` POST per confirmed CRN (form
/// body with that term and CRN) and then exactly one `plan/submitPlan/batch` POST whose JSON body only CREATES items
/// for those CRNs (`update` and `destroy` empty). Anything else — a second batch, an unknown CRN, another term, a
/// GET, an update / destroy — is refused. `revoke()` ends it (the exporter revokes when it finishes or fails).
public final class BannerExportAuthorization: @unchecked Sendable {
    public let termCode: String
    public let crns: [String]
    private let lock = NSLock()
    private var remainingAdds: Set<String>
    private var batchUsed = false
    private var revoked = false

    public init(termCode: String, crns: [String]) {
        self.termCode = termCode
        self.crns = crns
        remainingAdds = Set(crns)
    }

    public var isLive: Bool { lock.withLock { !revoked } }

    public func revoke() { lock.withLock { revoked = true } }

    /// Checks (and, when allowed, consumes) one export request.
    public func authorize(method: String, url: URL, body: Data?) -> BannerRequestGuard.Verdict {
        lock.lock()
        defer { lock.unlock() }
        guard !revoked else { return .deny("The export permission has ended — confirm the export again.") }
        guard method.uppercased() == "POST" else { return .deny("Blocked a \(method.uppercased()) to a plan endpoint.") }
        var path = url.path.lowercased()
        if path.hasSuffix("/") { path.removeLast() }
        guard url.query == nil || url.query?.isEmpty == true else { return .deny("Blocked a plan request with a query string.") }
        switch path {
        case BannerRequestGuard.addPlanItemPath:
            guard !batchUsed else { return .deny("Blocked adding a class after the plan was saved.") }
            let form = BannerPlanExport.parseForm(body ?? Data())
            guard form["term"] == termCode else { return .deny("Blocked adding a class for another term.") }
            guard form["section"] == "section" else { return .deny("Blocked a plan item that isn’t a section.") }
            guard let crn = form["courseReferenceNumber"], remainingAdds.contains(crn) else {
                return .deny("Blocked adding a class you didn’t confirm.")
            }
            let allowedKeys: Set<String> = ["term", "courseReferenceNumber", "section"]
            guard Set(form.keys).isSubset(of: allowedKeys) else { return .deny("Blocked a plan item with unexpected fields.") }
            remainingAdds.remove(crn)
            return .allow
        case BannerRequestGuard.submitPlanBatchPath:
            guard !batchUsed else { return .deny("Blocked a second plan save.") }
            guard remainingAdds.isEmpty else { return .deny("Blocked saving the plan before every confirmed class was added.") }
            guard let body, let value = try? JSONValue.parse(body), value.isObject else { return .deny("Blocked a plan save with an unreadable body.") }
            guard value["update"]?.arrayValue?.isEmpty == true, value["destroy"]?.arrayValue?.isEmpty == true else {
                return .deny("Blocked a plan save that would change or delete existing items.")
            }
            let created = value["create"]?.arrayValue ?? []
            let createdCRNs = created.compactMap { $0["courseReferenceNumber"]?.bannerString }
            guard created.count == crns.count, createdCRNs.count == created.count, Set(createdCRNs) == Set(crns),
                  created.allSatisfy({ ($0["term"]?.bannerString).map { $0 == termCode } ?? true }) else {
                return .deny("Blocked a plan save whose classes don’t match what you confirmed.")
            }
            batchUsed = true
            return .allow
        default:
            return .deny("Blocked a plan endpoint the export never uses (\(url.path)).")
        }
    }
}
