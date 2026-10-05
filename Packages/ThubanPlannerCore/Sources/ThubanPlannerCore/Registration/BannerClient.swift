import Foundation

/// Why a Banner call failed, in words the Schedule tab can show.
public enum BannerError: Error, LocalizedError, Equatable, Sendable {
    /// A request was refused by `BannerRequestGuard` before it left the app.
    case blocked(String)
    /// Banner sent a sign-in page (or HTML where JSON was expected) instead of the public class search.
    case signedOut
    case network(String)
    case http(Int)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .blocked(let message): return message
        case .signedOut: return "Banner sent a sign-in page instead of class data. Try Refresh in a minute."
        case .network(let message): return "Couldn’t reach Banner: \(message)"
        case .http(let status): return "Banner answered with an error (HTTP \(status))."
        case .unreadable(let message): return message
        }
    }
}

/// Sends one request. The app uses `URLSessionBannerTransport`; tests use a canned transport.
public protocol BannerTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession on an EPHEMERAL configuration with its own cookie jar: the public class search runs as an anonymous
/// Banner session and never carries the user's UNC Charlotte sign-in cookies (those stay in the web view's store).
/// Redirects are checked by `BannerRequestGuard` too, and a redirect to a sign-in page fails with `.signedOut`.
public final class URLSessionBannerTransport: NSObject, BannerTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!

    public override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        // The ephemeral configuration already has its own in-memory cookie jar (never the shared one).
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": "ThubanPlanner/1.0 (macOS; read-only schedule builder)"]
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw BannerError.unreadable("A request had no URL.") }
        if case .deny(let why) = BannerRequestGuard.check(method: request.httpMethod ?? "GET", url: url) { throw BannerError.blocked(why) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BannerError.unreadable("Banner sent a response that isn’t HTTP.") }
            if let final = http.url, BannerPage.isSignInURL(final) { throw BannerError.signedOut }
            return (data, http)
        } catch let error as BannerError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw BannerError.blocked("A redirect outside Banner was stopped.")
        } catch {
            throw BannerError.network(error.localizedDescription)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, !BannerPage.isSignInURL(url),
              BannerRequestGuard.check(method: request.httpMethod ?? "GET", url: url).isAllowed else {
            completionHandler(nil) // stop here; the 3xx itself is returned and `send` reports it
            return
        }
        completionHandler(request)
    }
}

/// Banner Student Registration class search, read-only. One logical session: a synchronizer token from the term
/// selection page, then `term/search` to pick the term (searches silently return nothing without it), then
/// `classSearch/resetDataForm` + `searchResults/searchResults` per course.
public actor BannerClient {
    public static let pageSize = 500

    private let transport: BannerTransport
    private let base: URL
    /// Banner's `uniqueSessionId` ("thuban" + epoch ms), fixed for the client's lifetime.
    public let uniqueSessionId: String
    private var token: String?
    private var selectedTerm: String?

    public init(transport: BannerTransport = URLSessionBannerTransport(), base: URL = BannerRequestGuard.base,
                uniqueSessionId: String = "thuban\(Int64(Date().timeIntervalSince1970 * 1000))") {
        self.transport = transport
        self.base = base
        self.uniqueSessionId = uniqueSessionId
    }

    // MARK: Requests

    func url(_ path: String, _ query: [(String, String)] = []) -> URL {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        // "+" in values must be encoded, URLComponents leaves it.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    private func request(_ method: String, _ url: URL, form: [(String, String)]? = nil, ajax: Bool = true) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        if ajax { r.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With") }
        if let token { r.setValue(token, forHTTPHeaderField: "X-Synchronizer-Token") }
        if let form {
            r.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            r.httpBody = Self.formBody(form).data(using: .utf8)
        }
        return r
    }

    static func formBody(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return pairs.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
    }

    private func send(_ request: URLRequest, expectJSON: Bool) async throws -> Data {
        guard let url = request.url else { throw BannerError.unreadable("A request had no URL.") }
        if case .deny(let why) = BannerRequestGuard.check(method: request.httpMethod ?? "GET", url: url) { throw BannerError.blocked(why) }
        let (data, response) = try await transport.send(request)
        if let final = response.url, BannerPage.isSignInURL(final) { throw BannerError.signedOut }
        if (300..<400).contains(response.statusCode) { throw BannerError.signedOut }
        if response.statusCode == 401 || response.statusCode == 403 { throw BannerError.signedOut }
        guard (200..<300).contains(response.statusCode) else { throw BannerError.http(response.statusCode) }
        if expectJSON, BannerPage.looksLikeHTML(data) { throw BannerError.signedOut }
        return data
    }

    // MARK: API

    /// `classSearch/getTerms` — newest first.
    public func terms(max: Int = 30) async throws -> [BannerTerm] {
        let data = try await send(request("GET", url("classSearch/getTerms", [("searchTerm", ""), ("offset", "1"), ("max", String(max))])),
                                  expectJSON: true)
        do { return try BannerTerm.decodeList(data) } catch { throw BannerError.unreadable("Banner’s term list couldn’t be read.") }
    }

    /// Starts a fresh anonymous session: reads the synchronizer token from the term selection page.
    public func startSession() async throws {
        token = nil
        selectedTerm = nil
        let data = try await send(request("GET", url("term/termSelection", [("mode", "search")]), ajax: false), expectJSON: false)
        let html = String(decoding: data, as: UTF8.self)
        guard let found = BannerPage.meta("synchronizerToken", in: html), !found.isEmpty else {
            throw BannerError.unreadable("Banner’s class search page didn’t load as expected.")
        }
        token = found
    }

    /// `term/search?mode=search` — selects the term for this session (re-POSTed to switch terms).
    public func selectTerm(_ code: String) async throws {
        if token == nil { try await startSession() }
        let form: [(String, String)] = [("term", code), ("studyPath", ""), ("studyPathText", ""), ("startDatepicker", ""),
                                        ("endDatepicker", ""), ("uniqueSessionId", uniqueSessionId)]
        _ = try await send(request("POST", url("term/search", [("mode", "search")]), form: form), expectJSON: true)
        selectedTerm = code
    }

    /// Every section of one course in a term (paginates past 500). When Banner answers 0 sections the session is
    /// re-established once and the search retried (a lost term selection also yields 0).
    public func sections(subject: String, courseNumber: String, term code: String) async throws -> [BannerSection] {
        let first = try await searchAll(subject: subject, courseNumber: courseNumber, term: code)
        if !first.isEmpty { return first }
        try await startSession()
        try await selectTerm(code)
        return try await searchAll(subject: subject, courseNumber: courseNumber, term: code)
    }

    private func searchAll(subject: String, courseNumber: String, term code: String) async throws -> [BannerSection] {
        if selectedTerm != code { try await selectTerm(code) }
        var all: [BannerSection] = []
        var offset = 0
        while true {
            _ = try await send(request("POST", url("classSearch/resetDataForm"), form: []), expectJSON: false)
            let query: [(String, String)] = [
                ("txt_subject", subject.uppercased()), ("txt_courseNumber", courseNumber.uppercased()), ("txt_term", code),
                ("startDatepicker", ""), ("endDatepicker", ""), ("uniqueSessionId", uniqueSessionId),
                ("pageOffset", String(offset)), ("pageMaxSize", String(Self.pageSize)),
                ("sortColumn", "subjectDescription"), ("sortDirection", "asc"),
            ]
            let data = try await send(request("GET", url("searchResults/searchResults", query)), expectJSON: true)
            let page: BannerSearchPage
            do { page = try BannerSearchPage.decode(data) } catch { throw BannerError.unreadable("Banner’s class search couldn’t be read.") }
            // Banner's search matches course numbers by prefix ("2144" also finds "2144L"): keep exact matches.
            all += page.sections.filter { $0.subject.uppercased() == subject.uppercased() && $0.courseNumber.uppercased() == courseNumber.uppercased() }
            offset += Self.pageSize
            if page.sections.isEmpty || offset >= page.totalCount || offset > 5000 { break }
        }
        var seen = Set<String>()
        return all.filter { seen.insert($0.crn).inserted }
    }

    /// Every section of a whole SUBJECT in a term — one search (`txt_subject` only, 500 per page) instead of one per
    /// course; used for "which courses were offered". Re-establishes the session once when Banner answers 0.
    public func subjectSections(subject: String, term code: String) async throws -> [BannerSection] {
        let first = try await searchSubject(subject, term: code)
        if !first.isEmpty { return first }
        try await startSession()
        try await selectTerm(code)
        return try await searchSubject(subject, term: code)
    }

    private func searchSubject(_ subject: String, term code: String) async throws -> [BannerSection] {
        if selectedTerm != code { try await selectTerm(code) }
        var all: [BannerSection] = []
        var offset = 0
        _ = try await send(request("POST", url("classSearch/resetDataForm"), form: []), expectJSON: false)
        while true {
            let query: [(String, String)] = [
                ("txt_subject", subject.uppercased()), ("txt_term", code),
                ("startDatepicker", ""), ("endDatepicker", ""), ("uniqueSessionId", uniqueSessionId),
                ("pageOffset", String(offset)), ("pageMaxSize", String(Self.pageSize)),
                ("sortColumn", "subjectDescription"), ("sortDirection", "asc"),
            ]
            let data = try await send(request("GET", url("searchResults/searchResults", query)), expectJSON: true)
            let page: BannerSearchPage
            do { page = try BannerSearchPage.decode(data) } catch { throw BannerError.unreadable("Banner’s class search couldn’t be read.") }
            all += page.sections.filter { $0.subject.uppercased() == subject.uppercased() }
            offset += Self.pageSize
            if page.sections.isEmpty || offset >= page.totalCount || offset > 5000 { break }
        }
        var seen = Set<String>()
        return all.filter { seen.insert($0.crn).inserted }
    }

    /// `searchResults/fetchLinkedSections` — the sets of sections that must be taken with `crn`.
    public func linkedSections(term code: String, crn: String) async throws -> [[BannerSection]] {
        if selectedTerm != code { try await selectTerm(code) }
        let data = try await send(request("GET", url("searchResults/fetchLinkedSections", [("term", code), ("courseReferenceNumber", crn)])),
                                  expectJSON: true)
        do { return try BannerLinkedSections.decode(data) } catch { throw BannerError.unreadable("Linked sections couldn’t be read.") }
    }
}
