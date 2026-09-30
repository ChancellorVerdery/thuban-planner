import Foundation
import XCTest
@testable import ThubanPlannerCore

final class BannerTermTests: XCTestCase {
    func testCodeToTermKey() {
        XCTAssertEqual(BannerTermCode.termKey("202710"), "spring-2027")
        XCTAssertEqual(BannerTermCode.termKey("202660"), "summer-2026")
        XCTAssertEqual(BannerTermCode.termKey("202680"), "fall-2026")
        XCTAssertEqual(BannerTermCode.termKey("201950"), "summer-2019")
        XCTAssertEqual(BannerTermCode.termKey("201970"), "summer-2019")
        XCTAssertNil(BannerTermCode.termKey("202720"))
        XCTAssertNil(BannerTermCode.termKey("2027"))
        XCTAssertNil(BannerTermCode.termKey("abcd10"))
        XCTAssertNil(BannerTermCode.termKey("２０２７１０"))
    }

    func testTermKeyToCode() {
        XCTAssertEqual(BannerTermCode.code(forTermKey: "spring-2027"), "202710")
        XCTAssertEqual(BannerTermCode.code(forTermKey: "summer-2026"), "202660")
        XCTAssertEqual(BannerTermCode.code(forTermKey: "fall-2026"), "202680")
        XCTAssertNil(BannerTermCode.code(forTermKey: "winter-2026"))
        XCTAssertNil(BannerTermCode.code(forTermKey: "fall-2026.5"))
        XCTAssertNil(BannerTermCode.code(forTermKey: "fall"))
        for key in ["spring-2025", "summer-2025", "fall-2025", "spring-2030"] {
            XCTAssertEqual(BannerTermCode.termKey(BannerTermCode.code(forTermKey: key)!), key)
        }
    }

    func testDecodeTermsFixture() throws {
        let terms = try BannerTerm.decodeList(TestSupport.fixture("banner/getTerms.json"))
        XCTAssertGreaterThan(terms.count, 5)
        XCTAssertEqual(terms[0], BannerTerm(code: "202710", description: "Spring 2027", viewOnly: true))
        XCTAssertEqual(terms[1], BannerTerm(code: "202680", description: "Fall 2026", viewOnly: false))
        XCTAssertFalse(terms.contains { $0.description.contains("View Only") })
        XCTAssertEqual(terms[0].termKey, "spring-2027")
    }

    func testCleanDescriptionVariants() {
        XCTAssertEqual(BannerTermCode.cleanDescription("Spring 2027 (View Only)").description, "Spring 2027")
        XCTAssertEqual(BannerTermCode.cleanDescription("Spring  2027 ( view only )").description, "Spring 2027")
        XCTAssertFalse(BannerTermCode.cleanDescription("Fall 2026").viewOnly)
    }

    func testSplitCourseCode() {
        XCTAssertEqual(BannerText.splitCourseCode("MEGR 2144")?.subject, "MEGR")
        XCTAssertEqual(BannerText.splitCourseCode("megr2144")?.number, "2144")
        XCTAssertEqual(BannerText.canonicalCourseCode(" phys  2101l "), "PHYS 2101L")
        XCTAssertNil(BannerText.splitCourseCode("2144"))
        XCTAssertNil(BannerText.splitCourseCode("MEGR"))
        XCTAssertNil(BannerText.splitCourseCode("ME-GR 2144"))
        XCTAssertEqual(BannerText.collapse("Hybrid:  F2F &\tOnline (Sync) "), "Hybrid: F2F & Online (Sync)")
    }
}

final class BannerSectionDecodingTests: XCTestCase {
    func testMEGR2144Fixture() throws {
        let page = try BannerSearchPage.decode(TestSupport.fixture("banner/searchResults-MEGR2144.json"))
        XCTAssertEqual(page.totalCount, 8)
        XCTAssertEqual(page.sections.count, 8)
        let first = page.sections[0]
        XCTAssertEqual(first.crn, "20263")
        XCTAssertEqual(first.courseCode, "MEGR 2144")
        XCTAssertEqual(first.sequenceNumber, "001")
        XCTAssertEqual(first.title, "Intro to Solid Mechanics")
        XCTAssertEqual(first.credits, 3) // creditHours null → creditHourLow
        XCTAssertEqual(first.seatsAvailable, 51)
        XCTAssertEqual(first.instructors, [])
        XCTAssertEqual(first.meetings.count, 1)
        let m = first.meetings[0]
        XCTAssertEqual(m.days, [.monday, .wednesday, .friday])
        XCTAssertEqual(m.begin, 9 * 60 + 5)
        XCTAssertEqual(m.end, 9 * 60 + 55)
        XCTAssertEqual(m.startDate, 20270111)
        XCTAssertEqual(m.endDate, 20270506)
        XCTAssertEqual(m.location, "DUKE 276")
        XCTAssertEqual(m.summary, "MWF 9:05–9:55 AM")
        // C01 / C02 carry two meetings each.
        let c01 = try XCTUnwrap(page.sections.first { $0.sequenceNumber == "C01" })
        XCTAssertEqual(c01.meetings.count, 2)
        XCTAssertEqual(c01.timedMeetings.count, 2)
    }

    func testPHYSFixtureEdgeCases() throws {
        let page = try BannerSearchPage.decode(TestSupport.fixture("banner/searchResults-PHYS-202680.json"))
        XCTAssertEqual(page.sections.count, page.totalCount)
        // Double spaces collapsed.
        XCTAssertTrue(page.sections.contains { $0.instructionalMethod == "Hybrid: F2F & Online (Sync)" })
        XCTAssertFalse(page.sections.contains { $0.instructionalMethod.contains("  ") })
        // Faculty: primary first.
        let hybrid = try XCTUnwrap(page.sections.first { $0.crn == "10933" })
        XCTAssertEqual(hybrid.instructors.first, "Christopher Gerardy")
        XCTAssertEqual(hybrid.meetings.count, 3)
        // Seats can be zero or negative; decoding keeps the sign.
        XCTAssertTrue(page.sections.contains { $0.seatsAvailable <= 0 })
        for s in page.sections where s.seatsAvailable < 0 { XCTAssertFalse(s.hasOpenSeat); XCTAssertTrue(s.isFullOrWaitlisted) }
        // Meetings with null times are untimed and never conflict.
        let untimed = page.sections.flatMap(\.meetings).filter { !$0.isTimed }
        for m in untimed { XCTAssertFalse(m.conflicts(with: m)) }
        // Every CRN unique.
        XCTAssertEqual(Set(page.sections.map(\.crn)).count, page.sections.count)
    }

    func testNullTimesAndNegativeSeatsSynthetic() throws {
        let json = """
        {"success":true,"totalCount":1,"data":[{"courseReferenceNumber":12345,"term":"202710","subject":"MEGR","courseNumber":"3090",
        "sequenceNumber":"O01","courseTitle":"Senior  Design","creditHours":"3","seatsAvailable":-2,"waitCount":"4",
        "instructionalMethodDescription":"Online  (Asynchronous)","isSectionLinked":"N","faculty":[{"displayName":"B","primaryIndicator":false},{"displayName":"A","primaryIndicator":true}],
        "meetingsFaculty":[{"meetingTime":{"beginTime":null,"endTime":null,"monday":false,"startDate":"01/11/2027","endDate":"05/06/2027"}}]}]}
        """
        let page = try BannerSearchPage.decode(Data(json.utf8))
        let s = try XCTUnwrap(page.sections.first)
        XCTAssertEqual(s.crn, "12345")
        XCTAssertEqual(s.credits, 3)
        XCTAssertEqual(s.seatsAvailable, -2)
        XCTAssertEqual(s.waitCount, 4)
        XCTAssertEqual(s.title, "Senior Design")
        XCTAssertEqual(s.instructors, ["A", "B"])
        XCTAssertFalse(s.isLinked)
        XCTAssertTrue(s.hasNoSetTime)
        XCTAssertTrue(s.isOnline)
        XCTAssertEqual(s.timeSummary, "Online / TBA")
    }

    func testHTMLIsNotJSON() {
        XCTAssertThrowsError(try BannerSearchPage.decode(Data("<!DOCTYPE html><html></html>".utf8)))
        XCTAssertTrue(BannerPage.looksLikeHTML(Data("  <!doctype html>".utf8)))
        XCTAssertFalse(BannerPage.looksLikeHTML(Data("{\"a\":1}".utf8)))
    }

    func testLinkedSectionsFixtureAndShape() throws {
        XCTAssertEqual(try BannerLinkedSections.decode(TestSupport.fixture("banner/linkedSections-202680-10001.json")), [])
        let json = """
        {"linkedData":[[{"courseReferenceNumber":"2","subject":"X","courseNumber":"1","sequenceNumber":"L1","meetingsFaculty":[]}],
                       [{"courseReferenceNumber":"3","subject":"X","courseNumber":"1","sequenceNumber":"L2","meetingsFaculty":[]}]]}
        """
        let sets = try BannerLinkedSections.decode(Data(json.utf8))
        XCTAssertEqual(sets.map { $0.map(\.crn) }, [["2"], ["3"]])
    }

    func testClock() {
        XCTAssertEqual(BannerClock.minutes("0905"), 545)
        XCTAssertEqual(BannerClock.minutes("905"), 545)
        XCTAssertEqual(BannerClock.minutes("13:30"), 810)
        XCTAssertNil(BannerClock.minutes("2560"))
        XCTAssertNil(BannerClock.minutes(""))
        XCTAssertEqual(BannerClock.dateNumber("01/11/2027"), 20270111)
        XCTAssertEqual(BannerClock.dateNumber("2027-01-11"), 20270111)
        XCTAssertNil(BannerClock.dateNumber("13/40/2027"))
        XCTAssertEqual(BannerClock.label(545), "9:05 AM")
        XCTAssertEqual(BannerClock.label(12 * 60), "12:00 PM")
        XCTAssertEqual(BannerClock.range(675, 725), "11:15 AM–12:05 PM")
        XCTAssertEqual(BannerClock.range(545, 595), "9:05–9:55 AM")
    }
}

final class BannerRequestGuardTests: XCTestCase {
    let b = "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/"

    func url(_ s: String) -> URL { URL(string: s)! }

    func testAllowsReadOnlyCalls() {
        XCTAssertEqual(BannerRequestGuard.check(method: "GET", url: url(b + "classSearch/getTerms?searchTerm=&offset=1&max=100")), .allow)
        XCTAssertEqual(BannerRequestGuard.check(method: "GET", url: url(b + "term/termSelection?mode=search")), .allow)
        XCTAssertEqual(BannerRequestGuard.check(method: "POST", url: url(b + "term/search?mode=search")), .allow)
        XCTAssertEqual(BannerRequestGuard.check(method: "POST", url: url(b + "term/search?mode=plan")), .allow)
        XCTAssertEqual(BannerRequestGuard.check(method: "post", url: url(b + "classSearch/resetDataForm")), .allow)
        XCTAssertEqual(BannerRequestGuard.check(method: "GET", url: url(b + "searchResults/searchResults?txt_subject=MEGR&txt_courseNumber=2144")), .allow)
        XCTAssertEqual(BannerRequestGuard.check(method: "GET", url: url(b + "plan/selectPlan")), .allow)
        XCTAssertEqual(BannerRequestGuard.check(method: "GET", url: url(b + "registration/registration")), .allow) // "registration" ≠ "register"
    }

    func testDeniesWrites() {
        for path in ["plan/submitPlan", "plan/addPlanItem", "plan/deletePlan", "plan/makePreferred", "plan/savePlanNote",
                     "plan/markApproved", "term/saveTerm?mode=registration", "classRegistration/submit",
                     "classRegistration/addRegistrationItem", "classRegistration/addCRNRegistrationItems", "classRegistration/register",
                     "PLAN/SUBMITPLAN", "plan/sub%6DitPlan"] {
            XCTAssertFalse(BannerRequestGuard.check(method: "GET", url: url(b + path)).isAllowed, path)
            XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: url(b + path)).isAllowed, path)
            XCTAssertFalse(BannerRequestGuard.checkBrowser(url: url(b + path)).isAllowed, path)
        }
    }

    func testDeniesUnlistedPostsOtherMethodsAndHosts() {
        XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: url(b + "plan/getPlanEvents")).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: url(b + "term/searchx")).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "PUT", url: url(b + "term/search")).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "DELETE", url: url(b + "classSearch/getTerms")).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "GET", url: url("http://selfservice.uncc.edu/StudentRegistrationSsb/ssb/term/termSelection")).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "GET", url: url("https://example.com/StudentRegistrationSsb/ssb/x")).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "GET", url: url("https://selfservice.uncc.edu/OtherApp/x")).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "GET", url: url("https://selfservice.uncc.edu.evil.com/StudentRegistrationSsb/ssb/x")).isAllowed)
    }

    func testBrowserAllowsSignIn() {
        XCTAssertTrue(BannerRequestGuard.checkBrowser(url: url("https://webauth.uncc.edu/idp/profile/cas/login?TARGET=https%3A%2F%2Fselfservice.uncc.edu%2FStudentRegistrationSsb%2Flogin%2Fcas")).isAllowed)
        XCTAssertTrue(BannerRequestGuard.checkBrowser(url: url(b + "term/termSelection?mode=plan")).isAllowed)
    }

    func testContentRuleListIsValidJSON() throws {
        let data = Data(BannerRequestGuard.contentRuleListJSON.utf8)
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(rules.count, BannerRequestGuard.deniedFragments.count)
        let filters = rules.compactMap { ($0["trigger"] as? [String: Any])?["url-filter"] as? String }
        XCTAssertTrue(filters.contains(".*submitplan.*"))
        XCTAssertTrue(filters.contains(".*classregistration/submit.*"))
    }

    func testSignInURLDetection() {
        XCTAssertTrue(BannerPage.isSignInURL(url("https://webauth.uncc.edu/idp/profile/cas/login")))
        XCTAssertTrue(BannerPage.isSignInURL(url(b + "registration/registration")))
        XCTAssertFalse(BannerPage.isSignInURL(url(b + "term/termSelection?mode=plan")))
        XCTAssertFalse(BannerPage.isSignInURL(url(b + "classSearch/classSearch")))
        XCTAssertFalse(BannerPage.isSignInURL(url(b + "plan/selectPlan")))
    }
}

final class BannerPlanTests: XCTestCase {
    func testReconstructedFixture() throws {
        let root = try JSONValue.parse(TestSupport.fixture("banner/plan-example.json"))
        let bootstraps = try XCTUnwrap(root["window.bootstraps (embedded in plan/selectPlan HTML page)"])
        let plans = BannerPlanParser.plans(from: bootstraps)
        XCTAssertEqual(plans.count, 1)
        let plan = plans[0]
        XCTAssertEqual(plan.displayName, "My Spring Plan")
        XCTAssertTrue(plan.preferred)
        XCTAssertEqual(plan.totalCredits, 15)
        XCTAssertEqual(plan.courses, [BannerPlanCourse(term: "202710", subject: "MEGR", courseNumber: "2144", title: "Intro to Solid Mechanics",
                                                       crn: nil, section: nil, credits: 3, isRegistered: false)])
        XCTAssertEqual(plan.courses(inTerm: "202710").count, 1)
        XCTAssertEqual(plan.courses(inTerm: "202680").count, 0)
    }

    func testTolerantVariantsAndOrdering() throws {
        let json = """
        {"plans":[
          {"sequenceNumber":"2","description":"Backup","preferredIndicator":"N","planCourses":[
             {"term":"202710","subjectCourse":"PHYS2101","courseReferenceNumber":"","creditHours":"3"},
             {"term":"202710","subject":"megr","courseNumber":"2144","courseReferenceNumber":20263,"section":"001"},
             {"term":"202710","subject":"MEGR","courseNumber":"2144","courseReferenceNumber":null},
             {"subject":"ENGR","courseNumber":"3295","isRegistered":"Y"},
             {"nonsense":true}, 7
          ]},
          {"sequenceNumber":1,"description":"","preferredIndicator":true,"planCourses":[]}
        ],
        "selectedPlan":{"planHeader":{"sequenceNumber":1,"planCourses":[{"term":"202710","subject":"MATH","courseNumber":"2164"}]}}}
        """
        let plans = try BannerPlanParser.parse(bootstrapsJSON: Data(json.utf8))
        XCTAssertEqual(plans.map(\.sequenceNumber), [1, 2]) // preferred first
        XCTAssertEqual(plans[0].displayName, "Plan 1")
        XCTAssertEqual(plans[0].courses.map(\.courseCode), ["MATH 2164"]) // filled from selectedPlan.planHeader
        let backup = plans[1]
        XCTAssertEqual(backup.courses.count, 4)
        XCTAssertEqual(backup.courses[0].courseCode, "PHYS 2101")
        XCTAssertNil(backup.courses[0].crn) // "" → course-level
        XCTAssertEqual(backup.courses[1].crn, "20263")
        XCTAssertEqual(backup.courses[1].courseCode, "MEGR 2144")
        XCTAssertTrue(backup.courses[3].isRegistered)
        // One entry per code for a term; the CRN item wins; a term-less item counts for every term.
        let spring = backup.courses(inTerm: "202710")
        XCTAssertEqual(spring.map(\.courseCode), ["PHYS 2101", "MEGR 2144", "ENGR 3295"])
        XCTAssertEqual(spring[1].crn, "20263")
    }

    func testEmptyAndNullBootstraps() throws {
        XCTAssertEqual(try BannerPlanParser.parse(bootstrapsJSON: Data("null".utf8)), [])
        XCTAssertEqual(try BannerPlanParser.parse(bootstrapsJSON: Data("{\"usingDates\":false}".utf8)), [])
        XCTAssertThrowsError(try BannerPlanParser.parse(bootstrapsJSON: Data("<html>".utf8)))
    }

    func testHTMLFallback() throws {
        let html = """
        <html><head><script>
          window.bootstraps = {
             mode: 'plan', planCount: 1,
             plans: [{sequenceNumber: 3, description: 'Fall "A" plan', preferredIndicator: true,
                      planCourses: [{term: '202680', subject: 'PHYS', courseNumber: '2102', courseTitle: 'Physics {II}', courseReferenceNumber: undefined},]}],
          };
          window.appContext = '/x'
        </script></head></html>
        """
        let plans = try BannerPlanParser.parse(html: html)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].description, "Fall \"A\" plan")
        XCTAssertEqual(plans[0].courses.first?.title, "Physics {II}")
        XCTAssertNil(plans[0].courses.first?.crn)
        // The real term-selection page has a bootstraps literal with no plans.
        let real = String(decoding: try TestSupport.fixture("banner/termSelection-head.html"), as: UTF8.self)
        XCTAssertEqual(try BannerPlanParser.parse(html: real), [])
        XCTAssertEqual(try BannerPlanParser.parse(html: "<html></html>"), [])
    }

    func testMetaReading() throws {
        let html = String(decoding: try TestSupport.fixture("banner/termSelection-head.html"), as: UTF8.self)
        XCTAssertEqual(BannerPage.meta("synchronizerToken", in: html)?.count, 36)
        XCTAssertEqual(BannerPage.meta("fullName", in: html), "")
        XCTAssertEqual(BannerPage.meta("fullName", in: "<meta name=\"fullName\" content=\"Alex Morgan\"/>"), "Alex Morgan")
        XCTAssertEqual(BannerPage.meta("fullName", in: "<meta content='X Y' name='fullName'>"), "X Y")
        XCTAssertNil(BannerPage.meta("missing", in: html))
        XCTAssertEqual(BannerPage.forwardURL(Data(#"{"fwdURL":"/StudentRegistrationSsb/ssb/plan/selectPlan"}"#.utf8)), "/StudentRegistrationSsb/ssb/plan/selectPlan")
        XCTAssertNil(BannerPage.forwardURL(Data("<html>".utf8)))
    }
}

/// Canned transport: answers by path, records every request.
final class FakeBannerTransport: BannerTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var responder: (URLRequest) -> (Data, Int, URL?)

    init(responder: @escaping (URLRequest) -> (Data, Int, URL?)) { self.responder = responder }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (data, status, final) = responder(request)
        return (data, HTTPURLResponse(url: final ?? request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class BannerClientTests: XCTestCase {
    static func standard(searchFixture: String = "banner/searchResults-MEGR2144.json") -> FakeBannerTransport {
        FakeBannerTransport { request in
            let path = request.url!.path
            if path.hasSuffix("term/termSelection") {
                return (Data(#"<html><head><meta name="synchronizerToken" content="tok-123"/></head></html>"#.utf8), 200, nil)
            }
            if path.hasSuffix("term/search") { return (Data(#"{"fwdURL":"/x"}"#.utf8), 200, nil) }
            if path.hasSuffix("resetDataForm") { return (Data("true".utf8), 200, nil) }
            if path.hasSuffix("getTerms") { return ((try? TestSupport.fixture("banner/getTerms.json")) ?? Data(), 200, nil) }
            if path.hasSuffix("searchResults/searchResults") { return ((try? TestSupport.fixture(searchFixture)) ?? Data(), 200, nil) }
            return (Data(), 404, nil)
        }
    }

    func testSearchFlowAndHeaders() async throws {
        let transport = Self.standard()
        let client = BannerClient(transport: transport, uniqueSessionId: "thubantest")
        let sections = try await client.sections(subject: "megr", courseNumber: "2144", term: "202710")
        XCTAssertEqual(sections.count, 8)
        let paths = transport.requests.map { "\($0.httpMethod!) \($0.url!.path.replacingOccurrences(of: "/StudentRegistrationSsb/ssb/", with: ""))" }
        XCTAssertEqual(paths, ["GET term/termSelection", "POST term/search", "POST classSearch/resetDataForm", "GET searchResults/searchResults"])
        let termPost = transport.requests[1]
        XCTAssertEqual(termPost.value(forHTTPHeaderField: "X-Synchronizer-Token"), "tok-123")
        XCTAssertEqual(termPost.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        let body = String(decoding: termPost.httpBody ?? Data(), as: UTF8.self)
        XCTAssertEqual(body, "term=202710&studyPath=&studyPathText=&startDatepicker=&endDatepicker=&uniqueSessionId=thubantest")
        XCTAssertEqual(termPost.url?.query, "mode=search")
        let search = try XCTUnwrap(URLComponents(url: transport.requests[3].url!, resolvingAgainstBaseURL: false))
        let q = Dictionary(uniqueKeysWithValues: (search.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["txt_subject"], "MEGR")
        XCTAssertEqual(q["txt_courseNumber"], "2144")
        XCTAssertEqual(q["txt_term"], "202710")
        XCTAssertEqual(q["pageMaxSize"], "500")
        XCTAssertEqual(q["uniqueSessionId"], "thubantest")
        // A second course in the same term reuses the session (no new token / term POST).
        _ = try await client.sections(subject: "MEGR", courseNumber: "2144", term: "202710")
        XCTAssertEqual(transport.requests.count, 6)
        // Every request passed the guard.
        for r in transport.requests { XCTAssertTrue(BannerRequestGuard.check(method: r.httpMethod!, url: r.url!).isAllowed) }
    }

    func testExactCourseNumberMatch() async throws {
        // The PHYS fixture has PHYS 2101 and PHYS 2101L … a search for 2101 keeps only 2101.
        let transport = Self.standard(searchFixture: "banner/searchResults-PHYS-202680.json")
        let client = BannerClient(transport: transport, uniqueSessionId: "t")
        let sections = try await client.sections(subject: "PHYS", courseNumber: "2101", term: "202680")
        XCTAssertEqual(sections.count, 16)
        XCTAssertTrue(sections.allSatisfy { $0.courseCode == "PHYS 2101" })
    }

    func testZeroResultsRetriesOnceWithFreshSession() async throws {
        let transport = FakeBannerTransport { request in
            let path = request.url!.path
            if path.hasSuffix("term/termSelection") { return (Data(#"<meta name="synchronizerToken" content="t2"/>"#.utf8), 200, nil) }
            if path.hasSuffix("searchResults/searchResults") { return (Data(#"{"success":true,"totalCount":0,"data":[]}"#.utf8), 200, nil) }
            return (Data("{}".utf8), 200, nil)
        }
        let client = BannerClient(transport: transport, uniqueSessionId: "t")
        let sections = try await client.sections(subject: "MEGR", courseNumber: "9999", term: "202710")
        XCTAssertEqual(sections, [])
        XCTAssertEqual(transport.requests.filter { $0.url!.path.hasSuffix("termSelection") }.count, 2)
        XCTAssertEqual(transport.requests.filter { $0.url!.path.hasSuffix("searchResults") }.count, 2)
    }

    func testSignedOutSigns() async {
        let redirect = FakeBannerTransport { _ in (Data("<html>login</html>".utf8), 200, URL(string: "https://webauth.uncc.edu/idp/profile/cas/login")!) }
        do { _ = try await BannerClient(transport: redirect).terms(); XCTFail("expected signedOut") } catch { XCTAssertEqual(error as? BannerError, .signedOut) }
        let html = FakeBannerTransport { _ in (Data("<!DOCTYPE html><html></html>".utf8), 200, nil) }
        do { _ = try await BannerClient(transport: html).terms(); XCTFail("expected signedOut") } catch { XCTAssertEqual(error as? BannerError, .signedOut) }
        let server = FakeBannerTransport { _ in (Data(), 500, nil) }
        do { _ = try await BannerClient(transport: server).terms(); XCTFail("expected http") } catch { XCTAssertEqual(error as? BannerError, .http(500)) }
    }

    func testPagination() async throws {
        var pageCalls = 0
        let transport = FakeBannerTransport { request in
            let path = request.url!.path
            if path.hasSuffix("term/termSelection") { return (Data(#"<meta name="synchronizerToken" content="t"/>"#.utf8), 200, nil) }
            if path.hasSuffix("searchResults/searchResults") {
                pageCalls += 1
                let offset = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "pageOffset" }!.value!)!
                let rows = (0..<(offset == 0 ? 500 : 20)).map { i in
                    #"{"courseReferenceNumber":"\#(offset + i)","subject":"MATH","courseNumber":"1100","sequenceNumber":"\#(i)","meetingsFaculty":[]}"#
                }
                return (Data(#"{"totalCount":520,"data":[\#(rows.joined(separator: ","))]}"#.utf8), 200, nil)
            }
            return (Data("{}".utf8), 200, nil)
        }
        let sections = try await BannerClient(transport: transport).sections(subject: "MATH", courseNumber: "1100", term: "202710")
        XCTAssertEqual(sections.count, 520)
        XCTAssertEqual(pageCalls, 2)
    }
}

final class TimetableStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TimetableStore(directory: dir)
        XCTAssertEqual(try store.loadDocument(), .empty)
        var state = TimetableTermState(source: .bannerPlan, planSequence: 2, addedCourses: ["MATH 2164"], removedCourses: ["PHIL 3527"],
                                       excludedCRNs: ["20263"], pins: ["MEGR 2144": "21125"], unpinnedPlanCourses: ["PHYS 2101"],
                                       blocks: [TimetableBlock(id: "b1", day: .tuesday, start: 12 * 60, end: 13 * 60, label: "Work")],
                                       filters: TimetableFilters(openSeatsOnly: true, hideFullOrWaitlisted: false, allowOnline: false, campuses: ["Main Campus"]),
                                       sort: .leastGaps, selectedIndex: 4)
        state.selectedIndex = 4
        let doc = TimetableDocument(lastTermCode: "202710", terms: ["202710": state])
        try store.saveDocument(doc)
        XCTAssertEqual(try store.loadDocument(), doc)
        let attrs = try FileManager.default.attributesOfItem(atPath: store.documentURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        var cache = BannerCache()
        cache.terms = [BannerTerm(code: "202710", description: "Spring 2027", viewOnly: true)]
        let sections = try BannerSearchPage.decode(TestSupport.fixture("banner/searchResults-MEGR2144.json")).sections
        cache.store(.init(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), sections: sections), term: "202710", course: "megr2144")
        cache.plans["202710"] = .init(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                      plans: [BannerPlan(sequenceNumber: 1, description: "P", courses: [])], studentName: "S")
        try store.saveCache(cache)
        let loaded = store.loadCache()
        XCTAssertEqual(loaded, cache)
        XCTAssertEqual(loaded.sections(term: "202710", course: "MEGR 2144")?.sections.count, 8)
        try store.deleteCache()
        XCTAssertEqual(store.loadCache(), BannerCache())
    }

    func testTolerantDecoding() throws {
        let json = #"{"terms":{"202710":{"source":"nope","blocks":[{"id":"x","day":2,"start":600,"end":660,"label":"L"}],"filters":{"openSeatsOnly":true},"selectedIndex":-3}},"lastTermCode":5}"#
        let doc = try JSONDecoder().decode(TimetableDocument.self, from: Data(json.utf8))
        let state = doc.state("202710")
        XCTAssertEqual(state.source, .route)
        XCTAssertEqual(state.blocks.first?.day, .tuesday)
        XCTAssertTrue(state.filters.openSeatsOnly)
        XCTAssertTrue(state.filters.allowOnline)
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertNil(doc.lastTermCode)
        XCTAssertEqual(doc.state("209910"), TimetableTermState())
    }

    func testCorruptDocumentThrowsAndCacheIsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = TimetableStore(directory: dir)
        try Data("{nope".utf8).write(to: store.documentURL)
        try Data("{nope".utf8).write(to: store.cacheURL)
        XCTAssertThrowsError(try store.loadDocument())
        XCTAssertEqual(store.loadCache(), BannerCache())
    }

    func testSampleDataIsDeterministic() {
        let a = BannerSampleData.sections(course: "MEGR 3114", title: "Fluid Mechanics", termCode: "202710")
        let b = BannerSampleData.sections(course: "MEGR 3114", title: "Fluid Mechanics", termCode: "202710")
        XCTAssertEqual(a, b)
        XCTAssertGreaterThanOrEqual(a.count, 3)
        XCTAssertEqual(Set(a.map(\.crn)).count, a.count)
        XCTAssertEqual(BannerSampleData.terms(around: "spring-2027").map(\.code), ["202760", "202710", "202680", "202660", "202610", "202580"])
    }
}
