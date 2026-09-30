import Foundation

/// The Schedule tab is STRICTLY READ-ONLY against Banner: it never registers, never changes a plan, never saves a
/// term. Every request the app makes itself goes through `check(method:url:)` (allowlist + denylist), and every
/// navigation / fetch / XHR inside the sign-in and reader web views is checked against the denylist
/// (`checkBrowser`) and blocked by a content rule list compiled from `contentRuleListJSON`.
public enum BannerRequestGuard {
    public enum Verdict: Equatable, Sendable {
        case allow
        case deny(String)

        public var isAllowed: Bool { self == .allow }
    }

    public static let host = "selfservice.uncc.edu"
    public static let basePath = "/StudentRegistrationSsb/"
    public static let base = URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb")!

    /// Fragments that name a write anywhere in a URL (case-insensitive). "register" does not match "registration".
    public static let deniedFragments: [String] = [
        "submitplan", "addplanitem", "deleteplan", "makepreferred", "saveplannote", "markapproved", "saveterm",
        "classregistration/submit", "addregistrationitem", "addcrnregistrationitems", "register",
    ]

    /// The only POST endpoints the app may call (selecting a term for the session; clearing the search form).
    public static let allowedPostPaths: [String] = [
        "/studentregistrationssb/ssb/term/search",
        "/studentregistrationssb/ssb/classsearch/resetdataform",
    ]

    /// The denied fragment a URL contains, if any (path and query, lower-cased; percent-decoded too).
    public static func deniedFragment(in url: URL) -> String? {
        let raw = url.absoluteString.lowercased()
        let decoded = raw.removingPercentEncoding ?? raw
        let haystack = decoded.split(separator: "#", maxSplits: 1).first.map(String.init) ?? decoded
        return deniedFragments.first { haystack.contains($0) }
    }

    /// For requests the app builds itself: HTTPS to selfservice.uncc.edu under /StudentRegistrationSsb/ only; any
    /// GET that is not a denied write; POST only to the allowlisted paths; nothing else.
    public static func check(method: String, url: URL) -> Verdict {
        if let fragment = deniedFragment(in: url) { return .deny("Blocked a request that could change your registration or plan (\(fragment)).") }
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == host else {
            return .deny("Blocked a request outside Banner (\(url.host ?? url.absoluteString)).")
        }
        guard url.path.lowercased().hasPrefix(basePath.lowercased()) else { return .deny("Blocked a request outside Banner registration.") }
        switch method.uppercased() {
        case "GET", "HEAD":
            return .allow
        case "POST":
            let path = url.path.lowercased()
            let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
            return allowedPostPaths.contains(trimmed) ? .allow : .deny("Blocked a POST the Schedule tab never makes (\(url.path)).")
        default:
            return .deny("Blocked a \(method.uppercased()) request.")
        }
    }

    /// For the web views (the user's own sign-in and the plan reader): everything is allowed EXCEPT the denied writes.
    public static func checkBrowser(url: URL) -> Verdict {
        if let fragment = deniedFragment(in: url) { return .deny("Blocked a request that could change your registration or plan (\(fragment)).") }
        return .allow
    }

    /// WebKit content rules (`WKContentRuleListStore`) that block every denied fragment for all resource types,
    /// including fetch / XHR ("raw") and documents.
    public static var contentRuleListJSON: String {
        let rules = deniedFragments.map { fragment -> String in
            // Fragments are plain lower-case letters and "/", which WebKit's url-filter takes literally.
            let pattern = fragment.filter { $0.isLetter || $0 == "/" }
            return #"{"trigger":{"url-filter":".*"# + pattern + #".*","url-filter-is-case-sensitive":false},"action":{"type":"block"}}"#
        }
        return "[" + rules.joined(separator: ",") + "]"
    }
}
