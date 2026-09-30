import Foundation

/// Reads `<meta name="…" content="…">` values (the synchronizer token).
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
