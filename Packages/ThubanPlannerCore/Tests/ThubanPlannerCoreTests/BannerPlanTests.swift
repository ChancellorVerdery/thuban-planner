import XCTest
@testable import ThubanPlannerCore

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
}
