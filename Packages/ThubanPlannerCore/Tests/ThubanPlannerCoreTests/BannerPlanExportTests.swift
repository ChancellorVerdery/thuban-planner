import XCTest
@testable import ThubanPlannerCore

final class BannerPlanExportTests: XCTestCase {
    let term = "202710"

    private func section(_ crn: String, _ subject: String, _ number: String, seq: String = "001", credits: Double? = 3,
                         meetings: [BannerMeeting]? = nil) -> BannerSection {
        BannerSection(crn: crn, term: term, subject: subject, courseNumber: number, sequenceNumber: seq, title: "\(subject) \(number) title",
                      credits: credits, meetings: meetings ?? [BannerMeeting(days: [.monday, .wednesday, .friday], begin: 545, end: 595)])
    }

    private func option() -> TimetableOption {
        let courses = [
            TimetableCourse(code: "MEGR 2144", choices: [TimetableChoice(sections: [section("20263", "MEGR", "2144")])]),
            // A linked lecture + lab set: both CRNs go into the plan, credits count once.
            TimetableCourse(code: "PHYS 2101", choices: [TimetableChoice(sections: [
                section("10001", "PHYS", "2101", credits: 4, meetings: [BannerMeeting(days: [.tuesday, .thursday], begin: 600, end: 675)]),
                section("10002", "PHYS", "2101", seq: "L01", credits: 4, meetings: [BannerMeeting(days: [.tuesday], begin: 780, end: 950)]),
            ])]),
            TimetableCourse(code: "ENGR 3295", choices: [TimetableChoice(sections: [section("30001", "ENGR", "3295", credits: 1,
                                                                                            meetings: [BannerMeeting(days: [], begin: nil, end: nil)])])]),
        ]
        return TimetableGenerator.generate(courses: courses, sorts: [.fewestDays]).options[0]
    }

    // MARK: Items

    func testItemsMapEverySectionWithCreditsAndTimes() {
        let items = BannerPlanExport.items(for: option())
        XCTAssertEqual(Set(items.map(\.crn)), ["20263", "10001", "10002", "30001"])
        let megr = items.first { $0.crn == "20263" }!
        XCTAssertEqual(megr.courseCode, "MEGR 2144")
        XCTAssertEqual(megr.section, "001")
        XCTAssertEqual(megr.term, term)
        XCTAssertEqual(megr.credits, 3)
        XCTAssertEqual(megr.times, "MWF 9:05–9:55 AM")
        XCTAssertEqual(items.first { $0.crn == "10002" }?.section, "L01")
        XCTAssertEqual(items.first { $0.crn == "30001" }?.times, "No set time")
        XCTAssertEqual(BannerPlanExport.totalCredits(option()), 8) // 3 + 4 (linked set once) + 1
    }

    // MARK: Name

    func testDefaultNameAndLimits() {
        XCTAssertEqual(BannerPlanExport.defaultName(termLabel: "Spring 2027", scheduleNumber: 3), "Thuban · Spring 2027 · Schedule 3")
        XCTAssertNil(BannerPlanExport.nameProblem("Thuban · Spring 2027 · Schedule 3"))
        XCTAssertNotNil(BannerPlanExport.nameProblem("   "))
        XCTAssertNotNil(BannerPlanExport.nameProblem(String(repeating: "x", count: 61)))
        XCTAssertNil(BannerPlanExport.nameProblem(String(repeating: "x", count: 60)))
        XCTAssertNotNil(BannerPlanExport.nameProblem("Thuban · Spring 2027 · Schedule 3", limit: 30))
        XCTAssertEqual(BannerPlanExport.cleanName("  My   plan \n"), "My plan")
    }

    // MARK: Requests

    func testAddPlanItemRequestMatchesThePage() {
        let r = BannerPlanExport.addPlanItemRequest(term: term, crn: "20263")
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.url.absoluteString, "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/plan/addPlanItem")
        XCTAssertEqual(r.contentType, "application/x-www-form-urlencoded; charset=UTF-8")
        XCTAssertEqual(r.bodyText, "term=202710&courseReferenceNumber=20263&section=section")
        XCTAssertEqual(BannerPlanExport.parseForm(r.body), ["term": term, "courseReferenceNumber": "20263", "section": "section"])
    }

    func testSubmitPlanBodyIsCreateOnlyWithTheName() throws {
        let model = try JSONValue.parse(TestSupport.fixture("banner/addPlanItem-success.json"))["model"]!
        let r = BannerPlanExport.submitPlanRequest(models: [model], name: "  Thuban · Spring 2027 · Schedule 3 ")
        XCTAssertEqual(r.url.absoluteString, "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/plan/submitPlan/batch")
        XCTAssertEqual(r.contentType, "application/json")
        let body = try JSONValue.parse(r.body)
        XCTAssertEqual(body["update"], .array([]))
        XCTAssertEqual(body["destroy"], .array([]))
        let created = try XCTUnwrap(body["create"]?.arrayValue)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created[0]["headerDescription"], .string("Thuban · Spring 2027 · Schedule 3"))
        XCTAssertEqual(created[0]["headerComment"], .null)
        XCTAssertNil(created[0]["messages"])
        XCTAssertEqual(created[0]["courseReferenceNumber"], .string("20263"))
        XCTAssertEqual(created[0]["courseTitle"], .string("Intro to Solid Mechanics")) // Banner's own model is sent back as-is
    }

    func testPlannedRequestsDryRun() {
        let items = BannerPlanExport.items(for: option())
        let requests = BannerPlanExport.plannedRequests(items: items, name: "N")
        XCTAssertEqual(requests.count, items.count + 1)
        XCTAssertTrue(requests.dropLast().allSatisfy { $0.url == BannerPlanExport.addPlanItemURL })
        XCTAssertEqual(requests.last?.url, BannerPlanExport.submitPlanBatchURL)
        XCTAssertTrue(requests[0].logLine.hasPrefix("POST https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/plan/addPlanItem"))
        XCTAssertTrue(BannerPlanExport.isDryRun(["THUBAN_PLANNER_EXPORT_DRY_RUN": "1"]))
        XCTAssertFalse(BannerPlanExport.isDryRun([:]))
        // The whole planned sequence passes one authorization, in order — and nothing more.
        let auth = BannerExportAuthorization(termCode: term, crns: items.map(\.crn))
        for r in requests { XCTAssertEqual(BannerRequestGuard.check(method: r.method, url: r.url, body: r.body, export: auth), .allow, r.logLine) }
        XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: requests[0].url, body: requests[0].body, export: auth).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: requests.last!.url, body: requests.last!.body, export: auth).isAllowed)
    }

    // MARK: Responses

    func testParseAddPlanItem() throws {
        guard case .added(let model) = BannerPlanExport.parseAddPlanItem(try TestSupport.fixture("banner/addPlanItem-success.json"), crn: "20263") else {
            return XCTFail("expected a model")
        }
        XCTAssertEqual(model["courseReferenceNumber"], .string("20263"))
        XCTAssertEqual(BannerPlanExport.parseAddPlanItem(Data(#"{"success":false,"message":"Section is closed"}"#.utf8), crn: "1"),
                       .rejected("CRN 1: Section is closed"))
        XCTAssertEqual(BannerPlanExport.parseAddPlanItem(Data(#"{"success":false}"#.utf8), crn: "1"), .rejected("CRN 1: Banner didn’t add CRN 1."))
        guard case .rejected(let html) = BannerPlanExport.parseAddPlanItem(Data("<!DOCTYPE html><html>".utf8), crn: "1") else { return XCTFail() }
        XCTAssertTrue(html.contains("sign-in"))
    }

    func testParseSubmitPlan() throws {
        XCTAssertEqual(BannerPlanExport.parseSubmitPlan(try TestSupport.fixture("banner/submitPlan-success.json")),
                       .saved(sequenceNumber: 3, description: "Thuban · Spring 2027 · Schedule 3"))
        XCTAssertEqual(BannerPlanExport.parseSubmitPlan(Data(#"{"success":false,"message":[{"message":"You have reached the maximum number of plans.","type":"error"}]}"#.utf8)),
                       .rejected("You have reached the maximum number of plans."))
        XCTAssertEqual(BannerPlanExport.parseSubmitPlan(Data(#"{"data":{"create":[{"messages":[{"type":"error","message":"Bad CRN"}]}]}}"#.utf8)),
                       .rejected("Bad CRN"))
    }

    // MARK: Plan pages

    func testPlanPageInfoAndMaxPlans() throws {
        let full = try BannerPlanPageInfo.parse(bootstrapsJSON: Data(#"""
        {"planCount":5,"maxPlans":5,"plans":[{"sequenceNumber":1,"description":"A","planCourses":[]}],"selectedPlan":{"planHeader":{"sequenceNumber":1,"planCourses":[{"subject":"X","courseNumber":"1"}]}}}
        """#.utf8))
        XCTAssertTrue(full.isFull)
        XCTAssertFalse(full.isNewEmptyPlan)
        XCTAssertEqual(full.plans.map(\.sequenceNumber), [1])
        let fresh = try BannerPlanPageInfo.parse(bootstrapsJSON: Data(#"{"planCount":"2","maxPlans":"5","selectedPlan":{"planHeader":{"sequenceNumber":null,"planCourses":[]}}}"#.utf8))
        XCTAssertFalse(fresh.isFull)
        XCTAssertTrue(fresh.isNewEmptyPlan)
        XCTAssertTrue(fresh.plans.isEmpty) // the empty new-plan header is never counted as a plan
        let unknown = try BannerPlanPageInfo.parse(bootstrapsJSON: Data("{}".utf8))
        XCTAssertFalse(unknown.isFull)
        XCTAssertTrue(unknown.isNewEmptyPlan)
    }

    func testVerification() {
        let plan = BannerPlan(sequenceNumber: 3, description: "Thuban · Spring 2027 · Schedule 3", courses: [
            BannerPlanCourse(term: term, subject: "MEGR", courseNumber: "2144", crn: "20263"),
            BannerPlanCourse(term: term, subject: "PHYS", courseNumber: "2101", crn: "10001"),
        ])
        let old = BannerPlan(sequenceNumber: 1, description: "Thuban · Spring 2027 · Schedule 3", courses: [])
        let name = "Thuban · Spring 2027 · Schedule 3"
        XCTAssertEqual(BannerPlanExport.verify(plans: [old, plan], name: name, sequenceNumber: 3, term: term, crns: ["20263", "10001"], previousSequences: [1]),
                       .verified(plan))
        // Without the sequence number, a plan that wasn't there before wins over an older one with the same name.
        XCTAssertEqual(BannerPlanExport.verify(plans: [old, plan], name: name, sequenceNumber: nil, term: term, crns: ["20263", "10001"], previousSequences: [1]),
                       .verified(plan))
        XCTAssertEqual(BannerPlanExport.verify(plans: [plan], name: name, sequenceNumber: 3, term: term, crns: ["20263", "10001", "30001"], previousSequences: []),
                       .mismatch(plan, missing: ["30001"], extra: []))
        XCTAssertEqual(BannerPlanExport.verify(plans: [old], name: "Other", sequenceNumber: nil, term: term, crns: ["1"], previousSequences: [1]), .notFound)
    }
}

final class BannerExportGuardTests: XCTestCase {
    let b = "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/"
    let term = "202710"
    func url(_ s: String) -> URL { URL(string: s)! }

    func testPlanCreationDeniedWithoutAuthorization() {
        let add = BannerPlanExport.addPlanItemRequest(term: term, crn: "20263")
        XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: add.url, body: add.body).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: BannerPlanExport.submitPlanBatchURL).isAllowed)
        XCTAssertFalse(BannerRequestGuard.checkBrowser(url: add.url).isAllowed)
        XCTAssertFalse(BannerRequestGuard.checkBrowser(url: BannerPlanExport.submitPlanBatchURL).isAllowed)
    }

    func testRegistrationAndExistingPlanWritesNeverAllowed() {
        let auth = BannerExportAuthorization(termCode: term, crns: ["20263"])
        for path in ["classRegistration/submitRegistration/batch", "classRegistration/addRegistrationItem", "classRegistration/addCRNRegistrationItems",
                     "classRegistration/classRegistration", "term/saveTerm?mode=registration", "registration/register",
                     "plan/deletePlan", "plan/makePreferred?preferred=1", "plan/savePlanNote", "plan/markApproved", "plan/DELETEPLAN",
                     "plan/delete%50lan"] {
            XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: url(b + path), body: Data(), export: auth).isAllowed, path)
            XCTAssertFalse(BannerRequestGuard.check(method: "GET", url: url(b + path), export: auth).isAllowed, path)
            XCTAssertFalse(BannerRequestGuard.checkBrowser(url: url(b + path)).isAllowed, path)
        }
        // None of those consumed the authorization.
        let add = BannerPlanExport.addPlanItemRequest(term: term, crn: "20263")
        XCTAssertEqual(BannerRequestGuard.check(method: "POST", url: add.url, body: add.body, export: auth), .allow)
    }

    func testAuthorizationIsScopedToTheConfirmedExport() {
        let auth = BannerExportAuthorization(termCode: term, crns: ["20263", "10001"])
        func add(_ crn: String, term t: String? = nil) -> BannerExportRequest { BannerPlanExport.addPlanItemRequest(term: t ?? term, crn: crn) }
        func check(_ r: BannerExportRequest, method: String = "POST") -> Bool {
            BannerRequestGuard.check(method: method, url: r.url, body: r.body, export: auth).isAllowed
        }
        XCTAssertFalse(check(add("99999")))                     // not confirmed
        XCTAssertFalse(check(add("20263", term: "202680")))     // other term
        XCTAssertFalse(check(add("20263"), method: "GET"))
        var extra = add("20263"); extra.body = Data("term=202710&courseReferenceNumber=20263&section=section&olr=true".utf8)
        XCTAssertFalse(check(extra))                            // unexpected fields
        var course = add("20263"); course.body = Data("term=202710&courseReferenceNumber=20263&section=course".utf8)
        XCTAssertFalse(check(course))
        // Saving before every class was added is refused.
        let early = BannerPlanExport.submitPlanRequest(models: [BannerPlanExport.dryRunModel(for: .init(term: term, crn: "20263", subject: "M", courseNumber: "1", section: "001", title: "", credits: 3, times: ""))], name: "N")
        XCTAssertFalse(check(early))
        XCTAssertTrue(check(add("20263")))
        XCTAssertFalse(check(add("20263")))                     // once per CRN
        XCTAssertTrue(check(add("10001")))
        // A batch with update / destroy, or other CRNs, is refused.
        func batch(_ json: String) -> BannerExportRequest {
            BannerExportRequest(method: "POST", url: BannerPlanExport.submitPlanBatchURL, contentType: "application/json", body: Data(json.utf8))
        }
        XCTAssertFalse(check(batch(#"{"create":[{"courseReferenceNumber":"20263","term":"202710"},{"courseReferenceNumber":"10001","term":"202710"}],"update":[{"id":1}],"destroy":[]}"#)))
        XCTAssertFalse(check(batch(#"{"create":[{"courseReferenceNumber":"20263","term":"202710"},{"courseReferenceNumber":"10001","term":"202710"}],"update":[],"destroy":[7]}"#)))
        XCTAssertFalse(check(batch(#"{"create":[{"courseReferenceNumber":"20263","term":"202710"}],"update":[],"destroy":[]}"#)))
        XCTAssertFalse(check(batch(#"{"create":[{"courseReferenceNumber":"20263","term":"202710"},{"courseReferenceNumber":"55555","term":"202710"}],"update":[],"destroy":[]}"#)))
        XCTAssertFalse(check(batch(#"{"create":[{"courseReferenceNumber":"20263","term":"202680"},{"courseReferenceNumber":"10001","term":"202710"}],"update":[],"destroy":[]}"#)))
        XCTAssertFalse(check(batch("not json")))
        var query = batch(#"{"create":[{"courseReferenceNumber":"20263"},{"courseReferenceNumber":"10001"}],"update":[],"destroy":[]}"#)
        query.url = url(b + "plan/submitPlan/batch?select=1")
        XCTAssertFalse(check(query))
        let good = batch(#"{"create":[{"courseReferenceNumber":"20263","term":"202710"},{"courseReferenceNumber":"10001"}],"update":[],"destroy":[]}"#)
        XCTAssertTrue(check(good))
        XCTAssertFalse(check(good))                             // one save only
        XCTAssertFalse(check(add("20263")))                     // nothing after the save
    }

    func testRevokedAuthorizationAllowsNothing() {
        let auth = BannerExportAuthorization(termCode: term, crns: ["20263"])
        auth.revoke()
        XCTAssertFalse(auth.isLive)
        let add = BannerPlanExport.addPlanItemRequest(term: term, crn: "20263")
        XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: add.url, body: add.body, export: auth).isAllowed)
    }

    func testOtherPlanEndpointsStayDeniedEvenWithAuthorization() {
        let auth = BannerExportAuthorization(termCode: term, crns: ["20263"])
        XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: url(b + "plan/submitPlan"), body: Data("{}".utf8), export: auth).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: url(b + "plan/getPlanEvents"), export: auth).isAllowed)
        XCTAssertFalse(BannerRequestGuard.check(method: "POST", url: url("https://example.com/StudentRegistrationSsb/ssb/plan/addPlanItem"),
                                                body: BannerPlanExport.addPlanItemRequest(term: term, crn: "20263").body, export: auth).isAllowed)
        // Read-only calls are unaffected.
        XCTAssertEqual(BannerRequestGuard.check(method: "POST", url: url(b + "term/search?mode=plan")), .allow)
        XCTAssertEqual(BannerRequestGuard.check(method: "GET", url: url(b + "plan/plan")), .allow)
        XCTAssertEqual(BannerRequestGuard.check(method: "GET", url: url(b + "plan/selectPlan")), .allow)
    }

    func testBrowserAllowsSignInAndPlanPages() {
        XCTAssertTrue(BannerRequestGuard.checkBrowser(url: url("https://webauth.uncc.edu/idp/profile/cas/login?TARGET=https%3A%2F%2Fselfservice.uncc.edu%2FStudentRegistrationSsb%2Flogin%2Fcas")).isAllowed)
        XCTAssertTrue(BannerRequestGuard.checkBrowser(url: url(b + "term/termSelection?mode=plan")).isAllowed)
        XCTAssertTrue(BannerRequestGuard.checkBrowser(url: url(b + "plan/plan")).isAllowed)
    }

    func testContentRuleLists() throws {
        func filters(_ json: String) throws -> [String] {
            let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
            return rules.compactMap { ($0["trigger"] as? [String: Any])?["url-filter"] as? String }
        }
        let signIn = try filters(BannerRequestGuard.contentRuleListJSON)
        XCTAssertEqual(signIn.count, BannerRequestGuard.deniedFragments.count)
        XCTAssertTrue(signIn.contains(".*submitplan.*"))
        XCTAssertTrue(signIn.contains(".*addplanitem.*"))
        XCTAssertTrue(signIn.contains(".*classregistration/.*"))
        let export = try filters(BannerRequestGuard.exportContentRuleListJSON)
        XCTAssertFalse(export.contains(".*submitplan.*"))
        XCTAssertFalse(export.contains(".*addplanitem.*"))
        XCTAssertTrue(export.contains(".*deleteplan.*"))
        XCTAssertTrue(export.contains(".*register.*"))
        XCTAssertTrue(BannerRequestGuard.pageFenceScript.contains("\"addplanitem\""))
        XCTAssertTrue(BannerRequestGuard.pageFenceScript.contains("\"submitregistration\""))
    }
}
