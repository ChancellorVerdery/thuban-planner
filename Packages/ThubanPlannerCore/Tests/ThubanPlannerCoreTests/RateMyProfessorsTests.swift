import Foundation
import XCTest
@testable import ThubanPlannerCore

enum RMPFixtures {
    static func teachers(_ name: String) throws -> [RMPTeacher] { try RMPTeacherSearch.decode(TestSupport.fixture("rmp/\(name)")) }
    static func name(_ raw: String) -> RMPPersonName { RMPPersonName.parse(raw)! }
}

final class RMPNameTests: XCTestCase {
    func testFirstLast() {
        let n = RMPFixtures.name("Ritchie  Dudley")
        XCTAssertEqual(n.displayName, "Ritchie Dudley")
        XCTAssertEqual(n.first, "ritchie")
        XCTAssertEqual(n.lastParts, ["dudley"])
        XCTAssertEqual(n.key, "ritchie dudley")
        XCTAssertEqual(n.searchTexts, ["Dudley"])
        XCTAssertFalse(n.commaForm)
    }

    func testLastCommaFirst() {
        let n = RMPFixtures.name("Dudley, Richard A.")
        XCTAssertTrue(n.commaForm)
        XCTAssertEqual(n.displayName, "Richard A. Dudley")
        XCTAssertEqual(n.first, "richard")
        XCTAssertEqual(n.lastWords, ["Dudley"])
        XCTAssertEqual(n.key, "richard a dudley")
        let v = RMPFixtures.name("Van Dyke, Mary Ann")
        XCTAssertEqual(v.lastParts, ["van", "dyke"])
        XCTAssertEqual(v.possibleLastParts, [["van", "dyke"]])
        XCTAssertEqual(v.searchTexts, ["Van Dyke", "Van", "Dyke"])
    }

    func testHyphenatedDiacriticsSuffixes() {
        let n = RMPFixtures.name("Farida Mohiuddin-Jacobs")
        XCTAssertEqual(n.lastParts, ["mohiuddin", "jacobs"])
        XCTAssertEqual(n.searchTexts, ["Mohiuddin-Jacobs", "Mohiuddin", "Jacobs"])
        let o = RMPFixtures.name("José  Núñez-O'Brien Jr.")
        XCTAssertEqual(o.displayName, "José Núñez-O'Brien")
        XCTAssertEqual(o.key, "jose nunez obrien")
        XCTAssertEqual(RMPFixtures.name("Dr. Greg Gbur").displayName, "Greg Gbur")
        let m = RMPFixtures.name("Mary Ann Van Dyke")
        XCTAssertEqual(m.possibleLastParts, [["ann", "van", "dyke"], ["van", "dyke"], ["dyke"]])
        XCTAssertEqual(m.searchTexts, ["Dyke", "Ann Van Dyke"])
    }

    func testPlaceholders() {
        for raw in ["", "  ", "TBA", "Staff", "To Be Announced", "Madonna"] { XCTAssertNil(RMPPersonName.parse(raw), raw) }
    }
}

final class RMPMatchTests: XCTestCase {
    func found(_ match: RMPMatch, file: StaticString = #filePath, line: UInt = #line) -> RMPRating? {
        if case .found(let r) = match { return r }
        XCTFail("expected found, got \(match)", file: file, line: line)
        return nil
    }

    func testExact() throws {
        let rating = found(RMPMatcher.match(name: RMPFixtures.name("Ritchie Dudley"), candidates: try RMPFixtures.teachers("teachers-1253-dudley.json"), subject: "PHYS"))
        XCTAssertEqual(rating?.profiles.map(\.legacyId), [3040576])
        XCTAssertEqual(rating?.avgRating, 4.1)
        XCTAssertEqual(rating?.numRatings, 7)
        XCTAssertEqual(rating?.wouldTakeAgainPercent, 87.5)
        XCTAssertNil(rating?.combinedDescription)
    }

    func testNicknameAndInitials() throws {
        let dudleys = try RMPFixtures.teachers("teachers-1253-dudley.json")
        XCTAssertEqual(found(RMPMatcher.match(name: RMPFixtures.name("Richard Dudley"), candidates: dudleys, subject: nil))?.profiles.map(\.firstName), ["Ritchie"])
        XCTAssertEqual(found(RMPMatcher.match(name: RMPFixtures.name("Dudley, R."), candidates: dudleys, subject: nil))?.profiles.map(\.firstName), ["Ritchie"])
        // Joanna Dudley has no ratings: found, but no score.
        let j = found(RMPMatcher.match(name: RMPFixtures.name("J Dudley"), candidates: dudleys, subject: nil))
        XCTAssertEqual(j?.numRatings, 0)
        XCTAssertNil(j?.avgRating)
        XCTAssertNil(j?.wouldTakeAgainPercent)
        // Prefix nickname: "Chris" / "Christopher".
        XCTAssertEqual(RMPMatcher.givenMatch("chris", "christopher"), .nickname)
        XCTAssertEqual(RMPMatcher.givenMatch("ed", "edward"), .nickname)
        XCTAssertEqual(RMPMatcher.givenMatch("jo", "joanna"), .none)
        XCTAssertEqual(RMPMatcher.givenMatch("j", "joanna"), .initial)
    }

    func testHyphenatedBothWays() throws {
        let pool = try RMPFixtures.teachers("teachers-1253-mohiuddin-jacobs.json") + RMPFixtures.teachers("teachers-1253-jacobs.json")
        XCTAssertEqual(found(RMPMatcher.match(name: RMPFixtures.name("Farida Mohiuddin-Jacobs"), candidates: pool, subject: "PHYS"))?.profiles.map(\.legacyId), [1710415])
        // Banner has only one of the two names; RMP has both (partial family + exact given).
        XCTAssertEqual(found(RMPMatcher.match(name: RMPFixtures.name("Farida Jacobs"), candidates: pool, subject: "PHYS"))?.profiles.map(\.legacyId), [1710415])
        XCTAssertEqual(found(RMPMatcher.match(name: RMPFixtures.name("Jacobs, Farida"), candidates: pool, subject: nil))?.profiles.map(\.legacyId), [1710415])
    }

    func testDuplicateProfilesOnOnePageAreCombined() throws {
        let smiths = try RMPFixtures.teachers("teachers-1253-smith.json")
        let r = found(RMPMatcher.match(name: RMPFixtures.name("Stuart Smith"), candidates: smiths, subject: "MEGR"))
        XCTAssertEqual(r?.profiles.map(\.legacyId), [98954, 1984832])
        XCTAssertEqual(r?.numRatings, 15)
        XCTAssertEqual(r?.avgRating ?? 0, (3.6 * 9 + 2.7 * 6) / 15, accuracy: 1e-9)
        XCTAssertEqual(r?.avgDifficulty ?? 0, (3.1 * 9 + 4 * 6) / 15, accuracy: 1e-9)
        XCTAssertEqual(r?.wouldTakeAgainPercent ?? 0, (66.6667 * 9 + 50 * 6) / 15, accuracy: 1e-9)
        XCTAssertEqual(r?.schoolCount, 1)
        XCTAssertEqual(r?.combinedDescription, "Combined from 2 profiles on UNC Charlotte’s page, weighted by number of ratings")
        // "Debra" and "Debra C" Smith are one person too; "Dorothy Smith-Ruiz" and "Jake Smithwick" are not Stuart.
        XCTAssertEqual(found(RMPMatcher.match(name: RMPFixtures.name("Debra Smith"), candidates: smiths, subject: nil))?.profiles.count, 2)
    }

    func testTwoUNCCPagesAreCombined() throws {
        let pool = try RMPFixtures.teachers("teachers-1253-dudley.json") + RMPFixtures.teachers("synthetic-teachers-19352-dudley.json")
            + RMPFixtures.teachers("teachers-19352-dudley.json")
        let r = found(RMPMatcher.match(name: RMPFixtures.name("Ritchie Dudley"), candidates: pool, subject: "PHYS"))
        XCTAssertEqual(r?.profiles.map(\.schoolLegacyId), [1253, 19352])
        XCTAssertEqual(r?.numRatings, 10)
        XCTAssertEqual(r?.avgRating ?? 0, (4.1 * 7 + 3.0 * 3) / 10, accuracy: 1e-9)       // 3.77
        XCTAssertEqual(r?.avgDifficulty ?? 0, (2.6 * 7 + 3.2 * 3) / 10, accuracy: 1e-9)   // 2.78
        XCTAssertEqual(r?.wouldTakeAgainPercent ?? 0, 87.5, accuracy: 1e-9)                // the -1 page is skipped
        XCTAssertEqual(r?.combinedDescription, "Combined from 2 UNC Charlotte pages, weighted by number of ratings")
    }

    func testAmbiguousAndDepartment() throws {
        let zhangs = try RMPFixtures.teachers("teachers-1253-zhang.json")
        guard case .ambiguous(let list) = RMPMatcher.match(name: RMPFixtures.name("Y. Zhang"), candidates: zhangs, subject: nil) else { return XCTFail() }
        XCTAssertEqual(Set(list.map(\.firstName)), ["Yong", "Yilei"])
        XCTAssertEqual(found(RMPMatcher.match(name: RMPFixtures.name("Y. Zhang"), candidates: zhangs, subject: "ECGR"))?.profiles.map(\.firstName), ["Yong"])
        if case .ambiguous = RMPMatcher.match(name: RMPFixtures.name("Y. Zhang"), candidates: zhangs, subject: "PHYS") {} else { XCTFail() }
        // An exact name is never ambiguous.
        XCTAssertEqual(found(RMPMatcher.match(name: RMPFixtures.name("Yong Zhang"), candidates: zhangs, subject: "PHYS"))?.profiles.map(\.legacyId), [1631503])
        XCTAssertTrue(RMPDepartments.fits(department: "Mechanical Engineering", subject: "megr"))
        XCTAssertTrue(RMPDepartments.fits(department: "Mathematics  Statistics", subject: "STAT"))
        XCTAssertFalse(RMPDepartments.fits(department: "Finance & Business Law", subject: "ECGR"))
        XCTAssertFalse(RMPDepartments.fits(department: "Physics", subject: "ZZZZ"))
    }

    func testNone() throws {
        XCTAssertEqual(RMPMatcher.match(name: RMPFixtures.name("Yuri Nesmelov"), candidates: try RMPFixtures.teachers("teachers-1253-nesmelov.json"), subject: "PHYS"), .notFound)
        XCTAssertEqual(RMPMatcher.match(name: RMPFixtures.name("Greg Gbur"), candidates: try RMPFixtures.teachers("teachers-1253-zhang.json"), subject: "PHYS"), .notFound)
        // Same name at another Charlotte school: never used.
        let queens = RMPSchool(id: "U2Nob29sLTQyNzI=", legacyId: 4272, name: "Queens University of Charlotte")
        let other = RMPTeacher(id: "x", legacyId: 1, firstName: "Ritchie", lastName: "Dudley", avgRating: 5, numRatings: 9, school: queens)
        XCTAssertEqual(RMPMatcher.match(name: RMPFixtures.name("Ritchie Dudley"), candidates: [other], subject: nil), .notFound)
    }

    func testWeightedAverage() {
        func t(_ id: Int, _ r: Double, _ n: Int, _ again: Double, d: Double = 3) -> RMPTeacher {
            RMPTeacher(id: "\(id)", legacyId: id, firstName: "A", lastName: "B", avgRating: r, avgDifficulty: d, numRatings: n, wouldTakeAgainPercent: again)
        }
        let zero = RMPRating(profiles: [t(1, 4.0, 10, 90, d: 2), t(2, 0, 0, -1, d: 0)])
        XCTAssertEqual(zero.avgRating, 4.0)
        XCTAssertEqual(zero.avgDifficulty, 2.0)
        XCTAssertEqual(zero.numRatings, 10)
        XCTAssertEqual(zero.wouldTakeAgainPercent, 90)
        let unknown = RMPRating(profiles: [t(1, 4.0, 10, 80), t(2, 2.0, 30, -1)])
        XCTAssertEqual(unknown.avgRating, 2.5)
        XCTAssertEqual(unknown.numRatings, 40)
        XCTAssertEqual(unknown.wouldTakeAgainPercent, 80)
        XCTAssertEqual(unknown.profiles.map(\.legacyId), [2, 1]) // most ratings first
        let none = RMPRating(profiles: [t(1, 0, 0, -1)])
        XCTAssertNil(none.avgRating)
        XCTAssertNil(none.avgDifficulty)
        XCTAssertNil(none.wouldTakeAgainPercent)
        XCTAssertEqual(none.numRatings, 0)
    }
}

final class RMPGuardAndClientTests: XCTestCase {
    func request(_ mutate: (inout URLRequest) -> Void = { _ in }) async throws -> URLRequest {
        var r = try await RMPClient(transport: FakeRMPTransport { _ in (Data(), 200) }).request(text: "Dudley", school: RateMyProfessors.unccMain)
        mutate(&r)
        return r
    }

    func testGuard() async throws {
        let plain = try await request()
        XCTAssertEqual(RMPRequestGuard.check(plain), .allow)
        let denied: [(inout URLRequest) -> Void] = [
            { $0.httpMethod = "GET" },
            { $0.url = URL(string: "http://www.ratemyprofessors.com/graphql") },
            { $0.url = URL(string: "https://evil.example.com/graphql") },
            { $0.url = URL(string: "https://www.ratemyprofessors.com/graphql?x=1") },
            { $0.url = URL(string: "https://www.ratemyprofessors.com/professor/1") },
            { $0.httpBody = nil },
            { $0.httpBody = Data(#"{"query":"mutation M { x }","variables":{"query":{"schoolID":"U2Nob29sLTEyNTM="}}}"#.utf8) },
            { $0.httpBody = Data(#"{"query":"query Q { x } mutation M { y }","variables":{"query":{"schoolID":"U2Nob29sLTEyNTM="}}}"#.utf8) },
            { $0.httpBody = Data(#"{"query":"query Q { x }","variables":{"query":{"text":"Smith"}}}"#.utf8) },
            { $0.httpBody = Data(#"{"query":"query Q { x }","variables":{"query":{"text":"Smith","schoolID":"U2Nob29sLTQyNzI="}}}"#.utf8) },
            { $0.httpBody = Data("not json".utf8) },
        ]
        for mutate in denied {
            let r = try await request(mutate)
            XCTAssertFalse(RMPRequestGuard.check(r).isAllowed, "\(r)")
        }
    }

    func testClientFlow() async throws {
        let transport = FakeRMPTransport.fixtures([
            "U2Nob29sLTEyNTM=|Dudley": "teachers-1253-dudley.json",
            "U2Nob29sLTE5MzUy|Dudley": "synthetic-teachers-19352-dudley.json",
        ])
        let client = RMPClient(transport: transport, minimumInterval: 0)
        let name = RMPFixtures.name("Ritchie Dudley")
        let candidates = try await client.candidates(for: name)
        XCTAssertEqual(candidates.map(\.legacyId), [3040576, 9999901]) // Joanna Dudley isn't a candidate
        XCTAssertEqual(transport.requests.count, 2)
        for r in transport.requests {
            XCTAssertEqual(r.httpMethod, "POST")
            XCTAssertEqual(r.url, RateMyProfessors.endpoint)
            XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Basic dGVzdDp0ZXN0")
            XCTAssertEqual(RMPRequestGuard.check(r), .allow)
        }
        XCTAssertEqual(Set(transport.bodies.map { $0.schoolID }), ["U2Nob29sLTEyNTM=", "U2Nob29sLTE5MzUy"])
        guard case .found(let rating) = RMPMatcher.match(name: name, candidates: candidates, subject: "PHYS") else { return XCTFail() }
        XCTAssertEqual(rating.schoolCount, 2)

        // Hyphenated: the full name and each part, on both pages.
        let hyphen = FakeRMPTransport.fixtures([
            "U2Nob29sLTEyNTM=|Mohiuddin-Jacobs": "teachers-1253-mohiuddin-jacobs.json",
            "U2Nob29sLTEyNTM=|Mohiuddin": "teachers-1253-mohiuddin.json",
            "U2Nob29sLTEyNTM=|Jacobs": "teachers-1253-jacobs.json",
        ])
        let found = try await RMPClient(transport: hyphen, minimumInterval: 0).candidates(for: RMPFixtures.name("Farida Mohiuddin-Jacobs"))
        XCTAssertEqual(found.map(\.legacyId), [1710415])
        XCTAssertEqual(hyphen.requests.count, 6)
    }

    func testClientErrorsAndScope() async throws {
        let server = RMPClient(transport: FakeRMPTransport { _ in (Data(), 500) }, minimumInterval: 0)
        do { _ = try await server.searchTeachers(text: "X", school: RateMyProfessors.unccMain); XCTFail() } catch { XCTAssertEqual(error as? RMPError, .http(500)) }
        let graphqlError = RMPClient(transport: FakeRMPTransport { _ in (Data(#"{"errors":[{"message":"nope"}]}"#.utf8), 200) }, minimumInterval: 0)
        do { _ = try await graphqlError.searchTeachers(text: "X", school: RateMyProfessors.unccMain); XCTFail() } catch {
            guard case .unreadable? = error as? RMPError else { return XCTFail("\(error)") }
        }
        let html = RMPClient(transport: FakeRMPTransport { _ in (Data("<html></html>".utf8), 200) }, minimumInterval: 0)
        do { _ = try await html.searchTeachers(text: "X", school: RateMyProfessors.unccMain); XCTFail() } catch {
            guard case .unreadable? = error as? RMPError else { return XCTFail("\(error)") }
        }
        // Only UNC Charlotte: another school is refused before anything is sent.
        let fake = FakeRMPTransport { _ in (Data(), 200) }
        let queens = RMPSchool(id: "U2Nob29sLTQyNzI=", legacyId: 4272, name: "Queens University of Charlotte")
        do { _ = try await RMPClient(transport: fake, minimumInterval: 0).searchTeachers(text: "X", school: queens); XCTFail() } catch {
            guard case .blocked? = error as? RMPError else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(fake.requests.isEmpty)
        // …and a school list with another school in it drops it.
        let scoped = FakeRMPTransport.fixtures([:])
        _ = try await RMPClient(transport: scoped, schools: [queens, RateMyProfessors.unccMain], minimumInterval: 0).candidates(for: RMPFixtures.name("A Dudley"))
        XCTAssertEqual(scoped.bodies.map(\.schoolID), ["U2Nob29sLTEyNTM="])
    }

    func testSchoolFixtureListsBothUNCCPages() throws {
        let json = try JSONSerialization.jsonObject(with: TestSupport.fixture("rmp/schools-unc-charlotte.json")) as! [String: Any]
        let edges = ((json["data"] as! [String: Any])["newSearch"] as! [String: Any])["schools"] as! [String: Any]
        let nodes = (edges["edges"] as! [[String: Any]]).map { $0["node"] as! [String: Any] }
        let uncc = nodes.filter { ($0["name"] as! String).hasPrefix("University of North Carolina at Char") }
        XCTAssertEqual(Set(uncc.map { $0["id"] as! String }), Set(RateMyProfessors.unccSchools.map(\.id)))
        XCTAssertEqual(RateMyProfessors.professorURL(legacyId: 3040576).absoluteString, "https://www.ratemyprofessors.com/professor/3040576")
        XCTAssertEqual(RateMyProfessors.searchURL(name: "Yuri Nesmelov").absoluteString,
                       "https://www.ratemyprofessors.com/search/professors/1253?q=Yuri%20Nesmelov")
    }
}

final class RMPCacheTests: XCTestCase {
    func testRoundTripFreshnessAndDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RMPCacheStore(directory: dir)
        XCTAssertEqual(store.load(), RMPCache())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var cache = RMPCache()
        let found = RMPFixtures.name("Ritchie Dudley"), missing = RMPFixtures.name("Yuri Nesmelov")
        cache.store(try RMPFixtures.teachers("teachers-1253-dudley.json"), for: found, at: now)
        cache.store([], for: missing, at: now)
        try store.save(cache, now: now)
        XCTAssertEqual(store.load(), cache)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        // Same person spelled differently shares the entry.
        XCTAssertNotNil(cache.entry(for: RMPFixtures.name("RITCHIE  DÜDLEY")))
        let day: TimeInterval = 24 * 3600
        XCTAssertNotNil(cache.freshEntry(for: found, now: now.addingTimeInterval(6 * day)))
        XCTAssertNil(cache.freshEntry(for: found, now: now.addingTimeInterval(8 * day)))
        XCTAssertNotNil(cache.freshEntry(for: missing, now: now.addingTimeInterval(1 * day)))
        XCTAssertNil(cache.freshEntry(for: missing, now: now.addingTimeInterval(3 * day)))
        XCTAssertNotNil(cache.entry(for: missing)) // stale entries stay usable offline
        // Very old entries are pruned on save.
        try store.save(cache, now: now.addingTimeInterval(90 * day))
        XCTAssertTrue(store.load().entries.isEmpty)
        try Data("garbage".utf8).write(to: store.url)
        XCTAssertEqual(store.load(), RMPCache())
        try store.delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testSampleDataCoversEveryState() {
        func m(_ raw: String, _ subject: String = "MEGR") -> RMPMatch {
            let n = RMPFixtures.name(raw)
            return RMPMatcher.match(name: n, candidates: RMPSampleData.candidates(for: n), subject: subject)
        }
        if case .found(let r) = m("Dana Whitfield") { XCTAssertEqual(r.schoolCount, 2); XCTAssertEqual(r.avgRating ?? 0, 4.208, accuracy: 1e-9) } else { XCTFail() }
        if case .ambiguous(let list) = m("Chen, L.") { XCTAssertEqual(list.count, 2) } else { XCTFail() }
        XCTAssertEqual(m("Priya Raman"), .notFound)
        if case .found(let r) = m("Owen Lindqvist") { XCTAssertNil(r.avgRating) } else { XCTFail() }
        if case .found(let r) = m("Tomas Reyes") { XCTAssertEqual(r.profiles.count, 2); XCTAssertEqual(r.avgRating, 3.5) } else { XCTFail() }
    }
}

/// Canned RMP answers; records requests.
final class FakeRMPTransport: RMPTransport, @unchecked Sendable {
    struct Body { var text: String; var schoolID: String }
    var requests: [URLRequest] = []
    var responder: (URLRequest) -> (Data, Int)

    init(responder: @escaping (URLRequest) -> (Data, Int)) { self.responder = responder }

    var bodies: [Body] {
        requests.compactMap { r in
            guard let body = r.httpBody, let o = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let q = (o["variables"] as? [String: Any])?["query"] as? [String: Any] else { return nil }
            return Body(text: q["text"] as? String ?? "", schoolID: q["schoolID"] as? String ?? "")
        }
    }

    /// "schoolID|text" → fixture; anything else answers an empty result.
    static func fixtures(_ map: [String: String]) -> FakeRMPTransport {
        FakeRMPTransport { r in
            let o = (try? JSONSerialization.jsonObject(with: r.httpBody ?? Data())) as? [String: Any]
            let q = (o?["variables"] as? [String: Any])?["query"] as? [String: Any]
            let key = "\(q?["schoolID"] as? String ?? "")|\(q?["text"] as? String ?? "")"
            if let file = map[key], let data = try? TestSupport.fixture("rmp/\(file)") { return (data, 200) }
            return (Data(#"{"data":{"newSearch":{"teachers":{"edges":[],"resultCount":0}}}}"#.utf8), 200)
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (data, status) = responder(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
