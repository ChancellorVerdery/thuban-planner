import Foundation

/// The Schedule tab is STRICTLY READ-ONLY against Banner and never signs in: it only reads the public class search.
/// Every request goes through `check(method:url:)` (allowlist + a denylist of every write endpoint, kept as defence
/// in depth).
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
}
