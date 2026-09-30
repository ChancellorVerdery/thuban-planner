import Foundation
import XCTest
@testable import ThubanPlannerCore

/// Builders for concise generator tests.
enum TT {
    static func meeting(_ days: String, _ begin: String?, _ end: String?, from: Int? = 20270111, to: Int? = 20270506) -> BannerMeeting {
        let map: [Character: BannerWeekday] = ["M": .monday, "T": .tuesday, "W": .wednesday, "R": .thursday, "F": .friday, "S": .saturday, "U": .sunday]
        return BannerMeeting(days: days.compactMap { map[$0] }, begin: begin.flatMap(BannerClock.minutes), end: end.flatMap(BannerClock.minutes),
                             startDate: from, endDate: to, building: "DUKE", room: "101")
    }

    static func section(_ code: String, _ crn: String, seats: Int = 10, wait: Int = 0, campus: String = "Main Campus",
                        method: String = "Face-to-Face Instruction", linked: Bool = false, _ meetings: BannerMeeting...) -> BannerSection {
        make(code, crn, "001", seats: seats, wait: wait, campus: campus, method: method, linked: linked, meetings)
    }

    static func section(_ code: String, _ crn: String, _ seq: String, seats: Int = 10, wait: Int = 0, campus: String = "Main Campus",
                        method: String = "Face-to-Face Instruction", linked: Bool = false, _ meetings: BannerMeeting...) -> BannerSection {
        make(code, crn, seq, seats: seats, wait: wait, campus: campus, method: method, linked: linked, meetings)
    }

    static func make(_ code: String, _ crn: String, _ seq: String, seats: Int = 10, wait: Int = 0, campus: String = "Main Campus",
                        method: String = "Face-to-Face Instruction", linked: Bool = false, _ meetings: [BannerMeeting]) -> BannerSection {
        let split = BannerText.splitCourseCode(code)!
        return BannerSection(crn: crn, term: "202710", subject: split.subject, courseNumber: split.number, sequenceNumber: seq, title: code,
                             instructionalMethod: method, campus: campus, seatsAvailable: seats, waitCount: wait, isLinked: linked, meetings: meetings)
    }

    static func course(_ code: String, _ sections: [BannerSection], excluded: Set<String> = [], pin: String? = nil) -> TimetableCourse {
        TimetableCourse(code: code, choices: TimetableChoice.build(sections: sections), excludedCRNs: excluded, pinnedCRN: pin)
    }
}

final class TimetableConflictTests: XCTestCase {
    func testMeetingConflicts() {
        let a = TT.meeting("MWF", "0905", "0955")
        XCTAssertTrue(a.conflicts(with: TT.meeting("W", "0930", "1045")))
        XCTAssertFalse(a.conflicts(with: TT.meeting("MWF", "0955", "1045")), "[begin, end) — touching is fine")
        XCTAssertFalse(a.conflicts(with: TT.meeting("TR", "0905", "0955")), "different days")
        XCTAssertFalse(a.conflicts(with: TT.meeting("MWF", nil, nil)), "online / TBA never conflicts")
        XCTAssertFalse(TT.meeting("", "0900", "1000").conflicts(with: TT.meeting("", "0900", "1000")), "no days = untimed")
    }

    func testDateRangesMustOverlap() {
        let firstHalf = TT.meeting("MW", "1000", "1115", from: 20270111, to: 20270305)
        let secondHalf = TT.meeting("MW", "1000", "1115", from: 20270315, to: 20270506)
        XCTAssertFalse(firstHalf.conflicts(with: secondHalf))
        XCTAssertTrue(firstHalf.conflicts(with: TT.meeting("M", "1100", "1200", from: 20270305, to: 20270506)), "one shared day is enough")
        XCTAssertTrue(firstHalf.conflicts(with: TT.meeting("M", "1100", "1200", from: nil, to: nil)), "missing dates = whole term")
    }

    func testBlocks() {
        let block = TimetableBlock(day: .monday, start: 12 * 60, end: 13 * 60, label: "Lunch")
        XCTAssertTrue(block.overlaps(TT.meeting("MWF", "1215", "1305")))
        XCTAssertFalse(block.overlaps(TT.meeting("MWF", "1300", "1350")))
        XCTAssertFalse(block.overlaps(TT.meeting("TR", "1215", "1305")))
        XCTAssertFalse(block.overlaps(TT.meeting("M", nil, nil)))
        XCTAssertEqual(TimetableBlock(day: .friday, start: 600, end: 540).start, 540, "start/end normalized")
        XCTAssertEqual(block.summary, "Mon 12:00–1:00 PM")
    }
}

final class TimetableGeneratorTests: XCTestCase {
    func testSimpleEnumerationAndConflicts() {
        let a = TT.course("MEGR 2144", [TT.section("MEGR 2144", "1", "001", TT.meeting("MWF", "0905", "0955")),
                                        TT.section("MEGR 2144", "2", "002", TT.meeting("MWF", "1115", "1205"))])
        let b = TT.course("PHYS 2101", [TT.section("PHYS 2101", "3", "001", TT.meeting("MW", "0930", "1045")),
                                        TT.section("PHYS 2101", "4", "002", TT.meeting("TR", "0930", "1045"))])
        let result = TimetableGenerator.generate(courses: [a, b])
        XCTAssertEqual(result.problems, [])
        XCTAssertFalse(result.capped)
        // 1+3 conflict (MW 9:30 overlaps MWF 9:05); the other three combinations fit.
        XCTAssertEqual(Set(result.options.map { $0.crns.joined(separator: ",") }), ["1,4", "2,3", "2,4"])
        for option in result.options {
            XCTAssertEqual(option.picks.map(\.course), ["MEGR 2144", "PHYS 2101"])
            let sections = option.sections
            for i in sections.indices { for j in sections.indices where j > i { XCTAssertFalse(sections[i].conflicts(with: sections[j])) } }
        }
    }

    func testOnlineSectionsNeverConflictAndCanBeFiltered() {
        let online = TT.section("MEGR 3090", "9", "O01", method: "Online (Asynchronous)", TT.meeting("", nil, nil))
        let a = TT.course("MEGR 3090", [online])
        let b = TT.course("PHYS 2101", [TT.section("PHYS 2101", "3", TT.meeting("MWF", "0800", "1700"))])
        XCTAssertEqual(TimetableGenerator.generate(courses: [a, b]).options.count, 1)
        let noOnline = TimetableGenerator.generate(courses: [a, b], filters: TimetableFilters(allowOnline: false))
        XCTAssertEqual(noOnline.options, [])
        guard case .noEligibleSections(let course, let report) = noOnline.problems.first else { return XCTFail("\(noOnline.problems)") }
        XCTAssertEqual(course, "MEGR 3090")
        XCTAssertEqual(report.rejections[.online], 1)
        XCTAssertTrue(noOnline.problems[0].message.contains("1 online"))
    }

    func testSeatFiltersCampusAndExclusions() {
        let sections = [
            TT.section("MEGR 2144", "1", "001", seats: 0, TT.meeting("MWF", "0800", "0850")),
            TT.section("MEGR 2144", "2", "002", seats: -3, wait: 2, TT.meeting("MWF", "0900", "0950")),
            TT.section("MEGR 2144", "3", "003", seats: 5, wait: 1, TT.meeting("MWF", "1000", "1050")),
            TT.section("MEGR 2144", "4", "004", seats: 5, campus: "Center City", TT.meeting("MWF", "1100", "1150")),
            TT.section("MEGR 2144", "5", "005", seats: 5, TT.meeting("MWF", "1200", "1250")),
        ]
        func crns(_ filters: TimetableFilters, excluded: Set<String> = []) -> [String] {
            TimetableGenerator.generate(courses: [TT.course("MEGR 2144", sections, excluded: excluded)], filters: filters)
                .options.map { $0.crns[0] }.sorted()
        }
        XCTAssertEqual(crns(TimetableFilters()), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(crns(TimetableFilters(openSeatsOnly: true)), ["3", "4", "5"])
        XCTAssertEqual(crns(TimetableFilters(hideFullOrWaitlisted: true)), ["4", "5"])
        XCTAssertEqual(crns(TimetableFilters(campuses: ["Main Campus"])), ["1", "2", "3", "5"])
        XCTAssertEqual(crns(TimetableFilters(), excluded: ["1", "5"]), ["2", "3", "4"])
        let none = TimetableGenerator.generate(courses: [TT.course("MEGR 2144", sections, excluded: ["3", "4", "5"])],
                                               filters: TimetableFilters(openSeatsOnly: true))
        XCTAssertEqual(none.reports.first?.rejections, [.excluded: 3, .noOpenSeat: 2])
        XCTAssertEqual(none.problems.first?.message, "MEGR 2144: none of its 5 sections can be used — 3 excluded by you, 2 no open seat.")
    }

    func testPinning() {
        let sections = [TT.section("MEGR 2144", "1", "001", TT.meeting("MWF", "0800", "0850")),
                        TT.section("MEGR 2144", "2", "002", TT.meeting("MWF", "0900", "0950"))]
        let pinned = TimetableGenerator.generate(courses: [TT.course("MEGR 2144", sections, pin: "2")])
        XCTAssertEqual(pinned.options.map(\.crns), [["2"]])
        XCTAssertEqual(pinned.reports[0].rejections[.notPinned], 1)
        // A stale pin (the section vanished) is ignored.
        let stale = TimetableGenerator.generate(courses: [TT.course("MEGR 2144", sections, pin: "99")])
        XCTAssertEqual(stale.options.count, 2)
    }

    func testBlockedTimesRemoveSections() {
        let a = TT.course("MEGR 2144", [TT.section("MEGR 2144", "1", "001", TT.meeting("MWF", "0800", "0850")),
                                        TT.section("MEGR 2144", "2", "002", TT.meeting("TR", "0800", "0915"))])
        let blocks = [TimetableBlock(day: .monday, start: 7 * 60, end: 9 * 60, label: "Work")]
        let result = TimetableGenerator.generate(courses: [a], blocks: blocks)
        XCTAssertEqual(result.options.map(\.crns), [["2"]])
        XCTAssertEqual(result.reports[0].rejections[.blocked], 1)
        let all = TimetableGenerator.generate(courses: [a], blocks: blocks + [TimetableBlock(day: .thursday, start: 8 * 60 + 30, end: 9 * 60)])
        XCTAssertEqual(all.options, [])
        XCTAssertTrue(all.problems[0].message.contains("2 in a blocked time"), all.problems[0].message)
    }

    func testZeroResultReasons() {
        // No sections at all.
        let empty = TimetableGenerator.generate(courses: [TimetableCourse(code: "ENGR 3295", choices: [])])
        XCTAssertEqual(empty.problems, [.noSections(course: "ENGR 3295")])
        XCTAssertEqual(empty.problems[0].message, "ENGR 3295 has no sections this term.")
        // A pair that always clashes.
        let a = TT.course("A 1000", [TT.section("A 1000", "1", TT.meeting("MWF", "0900", "0950")), TT.section("A 1000", "2", "002", TT.meeting("MWF", "1000", "1050"))])
        let b = TT.course("B 1000", [TT.section("B 1000", "3", TT.meeting("MWF", "0930", "1030"))])
        let c = TT.course("C 1000", [TT.section("C 1000", "4", TT.meeting("TR", "0930", "1030"))])
        let clash = TimetableGenerator.generate(courses: [a, b, c])
        XCTAssertEqual(clash.problems, [.alwaysConflict(first: "A 1000", second: "B 1000")])
        // Pairwise fine, jointly impossible: A ∈ {9, 10}, B ∈ {9, 10}, C ∈ {9, 10} — three courses, two slots.
        func twoSlot(_ code: String, _ base: Int) -> TimetableCourse {
            TT.course(code, [TT.section(code, "\(base)", "001", TT.meeting("MWF", "0900", "0950")),
                             TT.section(code, "\(base + 1)", "002", TT.meeting("MWF", "1000", "1050"))])
        }
        let pigeon = TimetableGenerator.generate(courses: [twoSlot("A 1000", 10), twoSlot("B 1000", 20), twoSlot("C 1000", 30)])
        XCTAssertEqual(pigeon.problems, [.noCombination])
        XCTAssertEqual(pigeon.options, [])
        // No courses: nothing, and nothing wrong.
        XCTAssertEqual(TimetableGenerator.generate(courses: []), TimetableResult(options: [], capped: false, limit: 10_000, reports: [], problems: []))
    }

    func testLinkedSets() {
        let lecture = TT.section("CHEM 1251", "100", "001", linked: true, TT.meeting("MWF", "0900", "0950"))
        let labA = TT.section("CHEM 1251", "201", "L01", linked: true, TT.meeting("T", "0900", "1145"))
        let labB = TT.section("CHEM 1251", "202", "L02", linked: true, TT.meeting("R", "0900", "1145"))
        let badLab = TT.section("CHEM 1251", "203", "L03", linked: true, TT.meeting("M", "0900", "1145"))
        let choices = TimetableChoice.build(sections: [lecture, labA, labB, badLab],
                                            linkedSets: ["100": [[labA], [labB], [badLab]], "201": [[lecture]], "202": [[lecture]]])
        // Lecture+L01, lecture+L02, lecture+L03 (seen from both sides once), L03 alone (no sets known).
        XCTAssertEqual(choices.map(\.id), ["100+201", "100+202", "100+203", "203"])
        let course = TimetableCourse(code: "CHEM 1251", choices: choices)
        let other = TT.course("MATH 2164", [TT.section("MATH 2164", "300", TT.meeting("T", "1000", "1050"))])
        let result = TimetableGenerator.generate(courses: [course, other])
        // 100+201 clashes with MATH on Tuesday 10:00; 100+203 overlaps itself (Monday 9:00); 203 alone is fine.
        XCTAssertEqual(Set(result.options.map(\.picks[0].choice.id)), ["100+202", "203"])
        XCTAssertEqual(result.reports[0].rejections[.selfConflict], 1)
    }

    func testDuplicateCourseCodesMerge() {
        let s1 = TT.section("MEGR 2144", "1", TT.meeting("MWF", "0800", "0850"))
        let s2 = TT.section("MEGR 2144", "2", "002", TT.meeting("MWF", "0900", "0950"))
        let result = TimetableGenerator.generate(courses: [TT.course("MEGR 2144", [s1]), TT.course("megr2144", [s1, s2])])
        XCTAssertEqual(result.reports.count, 1)
        XCTAssertEqual(result.options.count, 2)
    }

    func testCapAndDeterminism() {
        // 4 courses × 12 non-conflicting sections each (different days / hours) = 20,736 combinations.
        func course(_ code: String, day: String) -> TimetableCourse {
            TT.course(code, (0..<12).map { i in
                TT.section(code, "\(code.prefix(1))\(i)", String(format: "%03d", i),
                           seats: i, TT.meeting(day, String(format: "%02d00", 7 + i), String(format: "%02d50", 7 + i)))
            })
        }
        let courses = [course("A 1000", day: "M"), course("B 1000", day: "T"), course("C 1000", day: "W"), course("D 1000", day: "R")]
        let result = TimetableGenerator.generate(courses: courses, sort: .mostSeats, limit: 1000)
        XCTAssertTrue(result.capped)
        XCTAssertEqual(result.options.count, 1000)
        let again = TimetableGenerator.generate(courses: courses.reversed(), sort: .mostSeats, limit: 1000)
        XCTAssertEqual(result.options.map(\.id), TimetableGenerator.generate(courses: courses, sort: .mostSeats, limit: 1000).options.map(\.id))
        XCTAssertEqual(again.options.count, 1000)
        let full = TimetableGenerator.generate(courses: courses, limit: 100_000)
        XCTAssertFalse(full.capped)
        XCTAssertEqual(full.options.count, 20_736)
        XCTAssertEqual(Set(full.options.map(\.id)).count, 20_736)
    }

    func testSorting() {
        // X: MWF 8:00 or TR 13:00; Y: MWF 9:00 or TR 17:00.
        let x = TT.course("X 1000", [TT.section("X 1000", "x1", "001", seats: 1, TT.meeting("MWF", "0800", "0850")),
                                     TT.section("X 1000", "x2", "002", seats: 30, TT.meeting("TR", "1300", "1415"))])
        let y = TT.course("Y 1000", [TT.section("Y 1000", "y1", "001", seats: 2, TT.meeting("MWF", "0900", "0950")),
                                     TT.section("Y 1000", "y2", "002", seats: 40, TT.meeting("TR", "1700", "1815"))])
        func first(_ sort: TimetableSort) -> [String] { TimetableGenerator.generate(courses: [x, y], sort: sort).options[0].crns }
        // Fewest days: x2+y2 (TR, but a 2:45 gap) vs x1+y1 (MWF, no gap): 2 days < 3 days.
        XCTAssertEqual(first(.fewestDays), ["x2", "y2"])
        XCTAssertEqual(first(.latestStart), ["x2", "y2"])
        XCTAssertEqual(first(.earliestFinish), ["x1", "y1"])
        // x1+y2 and x2+y1 have no gaps (one class a day); the tie goes to the later start.
        XCTAssertEqual(first(.leastGaps), ["x2", "y1"])
        XCTAssertEqual(first(.mostSeats), ["x2", "y2"])
        let m = TimetableGenerator.generate(courses: [x, y], sort: .leastGaps).options.first { $0.crns == ["x2", "y2"] }!.metrics
        XCTAssertEqual(m.classDays, 2)
        XCTAssertEqual(m.gapMinutes, 2 * (17 * 60 - (14 * 60 + 15)))
        XCTAssertEqual(m.earliestStart, 13 * 60)
        XCTAssertEqual(m.latestEnd, 18 * 60 + 15)
        XCTAssertEqual(m.openSeats, 70)
    }

    func testMetricsIgnoreNegativeSeatsAndUntimed() {
        let m = TimetableMetrics.of([TT.section("A 1000", "1", seats: -4, TT.meeting("", nil, nil)),
                                     TT.section("B 1000", "2", seats: 3, TT.meeting("M", "0900", "1000"), TT.meeting("M", "0930", "1100"), TT.meeting("M", "1200", "1300"))])
        XCTAssertEqual(m.openSeats, 3)
        XCTAssertEqual(m.classDays, 1)
        XCTAssertEqual(m.gapMinutes, 60) // 9:00–11:00 merged, then 12:00
    }

    func testRealFixtureTwoCourses() throws {
        let phys = try BannerSearchPage.decode(TestSupport.fixture("banner/searchResults-PHYS-202680.json")).sections
        let lecture = phys.filter { $0.courseCode == "PHYS 2101" }
        let lab = phys.filter { $0.courseCode == "PHYS 2101L" }
        XCTAssertFalse(lecture.isEmpty)
        XCTAssertFalse(lab.isEmpty)
        let result = TimetableGenerator.generate(courses: [TT.course("PHYS 2101", lecture), TT.course("PHYS 2101L", lab)])
        XCTAssertFalse(result.options.isEmpty)
        XCTAssertLessThanOrEqual(result.options.count, lecture.count * lab.count)
        for option in result.options { XCTAssertFalse(option.sections[0].conflicts(with: option.sections[1])) }
    }

    func testPerformanceSixCoursesTwentySections() {
        // 6 courses × 20 sections over a realistic grid of MWF / TR slots; some pairs clash. Must finish quickly.
        let slots: [(String, String, String)] = [("MWF", "0800", "0850"), ("MWF", "0905", "0955"), ("MWF", "1010", "1100"), ("MWF", "1115", "1205"),
                                                 ("MW", "1325", "1440"), ("MW", "1600", "1715"), ("TR", "0830", "0945"), ("TR", "1000", "1115"),
                                                 ("TR", "1130", "1245"), ("TR", "1300", "1415"), ("TR", "1430", "1545"), ("TR", "1730", "1845")]
        let courses = (0..<6).map { c -> TimetableCourse in
            let code = "C\(c) 1000"
            return TT.course(code, (0..<20).map { s in
                let slot = slots[(c * 5 + s * 7) % slots.count]
                return TT.section(code, "\(c)-\(s)", String(format: "%03d", s), seats: (s * 3 + c) % 17 - 3, TT.meeting(slot.0, slot.1, slot.2))
            })
        }
        let start = Date()
        let result = TimetableGenerator.generate(courses: courses, sort: .leastGaps)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(result.capped)
        XCTAssertEqual(result.options.count, TimetableGenerator.defaultLimit)
        XCTAssertLessThan(elapsed, 5, "generation took \(elapsed) s")
        // Deterministic.
        XCTAssertEqual(result.options.prefix(50).map(\.id), TimetableGenerator.generate(courses: courses, sort: .leastGaps).options.prefix(50).map(\.id))
        // Filtered (open seats only) still fine.
        let open = TimetableGenerator.generate(courses: courses, filters: TimetableFilters(openSeatsOnly: true))
        XCTAssertFalse(open.options.isEmpty)
        for option in open.options.prefix(200) { XCTAssertTrue(option.sections.allSatisfy(\.hasOpenSeat)) }
    }
}
