import Foundation

/// Why a Rate My Professors lookup failed.
public enum RMPError: Error, LocalizedError, Equatable, Sendable {
    case blocked(String)
    case network(String)
    case http(Int)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .blocked(let message): return message
        case .network(let message): return "Couldn’t reach Rate My Professors: \(message)"
        case .http(let status): return "Rate My Professors answered with an error (HTTP \(status))."
        case .unreadable(let message): return message
        }
    }
}

/// Every request to Rate My Professors goes through `check`: HTTPS POST to www.ratemyprofessors.com/graphql only,
/// a JSON body holding ONE read-only `query` (anything mentioning "mutation" is refused), scoped with a `schoolID`
/// that is one of the UNC Charlotte pages. Nothing else ever leaves the app.
public enum RMPRequestGuard {
    public enum Verdict: Equatable, Sendable {
        case allow
        case deny(String)
        public var isAllowed: Bool { self == .allow }
    }

    public static func check(_ request: URLRequest) -> Verdict {
        guard let url = request.url else { return .deny("A request had no URL.") }
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == RateMyProfessors.host else {
            return .deny("Blocked a request outside Rate My Professors (\(url.host ?? url.absoluteString)).")
        }
        guard url.path == "/graphql", url.query == nil, url.fragment == nil else { return .deny("Blocked a Rate My Professors request other than its search.") }
        guard (request.httpMethod ?? "GET").uppercased() == "POST" else { return .deny("Blocked a \(request.httpMethod ?? "GET") request to Rate My Professors.") }
        guard let body = request.httpBody, !body.isEmpty else { return .deny("Blocked an empty Rate My Professors request.") }
        let text = String(decoding: body, as: UTF8.self)
        if text.lowercased().contains("mutation") { return .deny("Blocked a Rate My Professors request that could change data (mutation).") }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let query = object["query"] as? String else { return .deny("Blocked a malformed Rate My Professors request.") }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("query ") || trimmed.hasPrefix("query(") || trimmed.hasPrefix("{") else {
            return .deny("Blocked a Rate My Professors request that isn’t a read-only query.")
        }
        guard let variables = object["variables"] as? [String: Any], let scoped = variables["query"] as? [String: Any],
              let schoolID = scoped["schoolID"] as? String, RateMyProfessors.school(id: schoolID) != nil else {
            return .deny("Blocked a Rate My Professors search outside UNC Charlotte.")
        }
        return .allow
    }
}

/// Sends one request. The app uses `URLSessionRMPTransport`; tests use a canned transport.
public protocol RMPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Ephemeral URLSession, no cookies, 15 s per request, redirects refused. Checks `RMPRequestGuard` first.
public final class URLSessionRMPTransport: NSObject, RMPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!

    public override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if case .deny(let why) = RMPRequestGuard.check(request) { throw RMPError.blocked(why) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw RMPError.unreadable("Rate My Professors sent a response that isn’t HTTP.") }
            return (data, http)
        } catch let error as RMPError {
            throw error
        } catch {
            throw RMPError.network(error.localizedDescription)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Read-only Rate My Professors search over UNC Charlotte's pages (GraphQL `newSearch.teachers`, the query RMP's
/// own site sends). Requests are sequential and paced.
public actor RMPClient {
    public static let pageSize = 50
    /// The one query the app sends.
    public static let teacherSearchQuery = """
    query TeacherSearch($query: TeacherSearchQuery!, $count: Int) { newSearch { teachers(query: $query, first: $count) { \
    resultCount edges { node { id legacyId firstName lastName department avgRating avgDifficulty numRatings \
    wouldTakeAgainPercent school { id legacyId name } } } } } }
    """

    private let transport: RMPTransport
    private let schools: [RMPSchool]
    private let minimumInterval: Double
    private var lastSent: Date?
    public private(set) var requestCount = 0

    /// `minimumInterval` seconds between two requests (tests pass 0).
    public init(transport: RMPTransport = URLSessionRMPTransport(), schools: [RMPSchool] = RateMyProfessors.unccSchools,
                minimumInterval: Double = 0.6) {
        self.transport = transport
        self.schools = schools.filter { RateMyProfessors.school(id: $0.id) != nil }
        self.minimumInterval = minimumInterval
    }

    func request(text: String, school: RMPSchool) throws -> URLRequest {
        var r = URLRequest(url: RateMyProfessors.endpoint)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue(RateMyProfessors.publicAuthorization, forHTTPHeaderField: "Authorization")
        r.setValue("ThubanPlanner/1.0 (macOS; read-only)", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = [
            "query": Self.teacherSearchQuery,
            "variables": ["query": ["text": text, "schoolID": school.id], "count": Self.pageSize],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        r.timeoutInterval = 15
        return r
    }

    /// Profiles on one UNC Charlotte page whose name matches `text` (RMP's own name search).
    public func searchTeachers(text: String, school: RMPSchool) async throws -> [RMPTeacher] {
        let r = try request(text: text, school: school)
        if case .deny(let why) = RMPRequestGuard.check(r) { throw RMPError.blocked(why) }
        if let lastSent, minimumInterval > 0 {
            let wait = minimumInterval - Date().timeIntervalSince(lastSent)
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        }
        lastSent = Date()
        requestCount += 1
        let (data, response) = try await transport.send(r)
        guard (200..<300).contains(response.statusCode) else { throw RMPError.http(response.statusCode) }
        return try RMPTeacherSearch.decode(data).filter { RateMyProfessors.school(legacyId: $0.schoolLegacyId) != nil }
    }

    /// Every UNC Charlotte profile that could be `name` (searches each page with each of `name.searchTexts`), kept
    /// only when `RMPMatcher.isCandidate` — i.e. what the cache stores. Most ratings first.
    public func candidates(for name: RMPPersonName) async throws -> [RMPTeacher] {
        var found: [RMPTeacher] = []
        var seen = Set<String>()
        for school in schools {
            for text in name.searchTexts {
                for t in try await searchTeachers(text: text, school: school) where RMPMatcher.isCandidate(name, t) && seen.insert(t.id).inserted {
                    found.append(t)
                }
            }
        }
        return found.sorted { $0.numRatings != $1.numRatings ? $0.numRatings > $1.numRatings : $0.legacyId < $1.legacyId }
    }
}

/// Decodes `{"data":{"newSearch":{"teachers":{"edges":[{"node":{…}}]}}}}` tolerantly (nulls → defaults).
public enum RMPTeacherSearch {
    private struct Root: Decodable {
        struct DataField: Decodable { var newSearch: NewSearch? }
        struct NewSearch: Decodable { var teachers: Connection? }
        struct Connection: Decodable { var edges: [Edge]? }
        struct Edge: Decodable { var node: Node? }
        struct School: Decodable { var id: String?; var legacyId: Int?; var name: String? }
        struct Node: Decodable {
            var id: String?
            var legacyId: Int?
            var firstName: String?
            var lastName: String?
            var department: String?
            var avgRating: Double?
            var avgDifficulty: Double?
            var numRatings: Int?
            var wouldTakeAgainPercent: Double?
            var school: School?
        }
        struct GraphQLError: Decodable { var message: String? }
        var data: DataField?
        var errors: [GraphQLError]?
    }

    public static func decode(_ data: Data) throws -> [RMPTeacher] {
        let root: Root
        do { root = try JSONDecoder().decode(Root.self, from: data) } catch {
            throw RMPError.unreadable("Rate My Professors’ answer couldn’t be read.")
        }
        if let errors = root.errors, !errors.isEmpty {
            throw RMPError.unreadable("Rate My Professors refused the search: \(errors.compactMap(\.message).joined(separator: "; "))")
        }
        guard let edges = root.data?.newSearch?.teachers?.edges else { throw RMPError.unreadable("Rate My Professors’ answer had an unexpected shape.") }
        return edges.compactMap { edge in
            guard let n = edge.node, let id = n.id, let legacy = n.legacyId, let schoolLegacy = n.school?.legacyId else { return nil }
            let school = RMPSchool(id: n.school?.id ?? "", legacyId: schoolLegacy, name: n.school?.name ?? "")
            return RMPTeacher(id: id, legacyId: legacy, firstName: n.firstName ?? "", lastName: n.lastName ?? "",
                              department: BannerText.collapse(n.department ?? ""), avgRating: n.avgRating ?? 0,
                              avgDifficulty: n.avgDifficulty ?? 0, numRatings: max(0, n.numRatings ?? 0),
                              wouldTakeAgainPercent: n.wouldTakeAgainPercent ?? -1, school: school)
        }
    }
}
