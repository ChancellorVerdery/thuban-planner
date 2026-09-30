import Foundation
import XCTest
@testable import ThubanPlannerCore

final class TimetableRatingTests: XCTestCase {
    private func section(_ code: String, _ crn: String, credits: Double? = 3, instructors: [String] = [], _ meeting: BannerMeeting) -> BannerSection {
        var s = TT.section(code, crn, meeting)
        s.credits = credits
        s.instructors = instructors
        return s
    }

    private func rating(_ value: Double, _ n: Int) -> RMPRating {
        RMPRating(profiles: [RMPTeacher(id: "\(value)-\(n)", legacyId: n, firstName: "A", lastName: "B", avgRating: value, numRatings: n)])
    }

    func testSectionRatingAndBuildExclusions() {
        XCTAssertEqual(TimetableRatings.sectionRating([rating(4, 10), rating(2, 30)]), 2.5)
        XCTAssertNil(TimetableRatings.sectionRating([rating(0, 0)]))
        let sections = [
            section("A 1", "a1", instructors: ["Found Person"], TT.meeting("MWF", "0800", "0850")),
            section("A 1", "a2", instructors: ["Missing Person"], TT.meeting("MWF", "0900", "0950")),
            section("A 1", "a3", instructors: ["Ambiguous Person"], TT.meeting("MWF", "1000", "1050")),
            section("A 1", "a4", instructors: ["Unrated Person"], TT.meeting("MWF", "1100", "1150")),
            section("A 1", "a5", instructors: [], TT.meeting("MWF", "1200", "1250")),
            section("A 1", "a6", instructors: ["Found Person", "Other Found", "Missing Person"], TT.meeting("MWF", "1300", "1350")),
            section("A 1", "a7", instructors: ["Not Looked Up"], TT.meeting("MWF", "1400", "1450")),
        ]
        let table = TimetableRatings.build(sections: sections) { name, _ in
            switch name {
            case "Found Person": return .found(self.rating(4.5, 10))
            case "Other Found": return .found(self.rating(3.0, 30))
            case "Missing Person": return .notFound
            case "Ambiguous Person": return .ambiguous([])
            case "Unrated Person": return .found(self.rating(0, 0))
            default: return nil
            }
        }
        XCTAssertEqual(table.bySection["a1"], 4.5)
        XCTAssertEqual(table.bySection["a6"] ?? 0, (4.5 * 10 + 3.0 * 30) / 40, accuracy: 1e-12)
        // Not on RMP, ambiguous, 0 ratings and unassigned score 2.5; a pending lookup stays out until it resolves.
        XCTAssertEqual(table.bySection["a2"], 2.5)
        XCTAssertEqual(table.bySection["a3"], 2.5)
        XCTAssertEqual(table.bySection["a4"], 2.5)
        XCTAssertEqual(table.bySection["a5"], 2.5)
        XCTAssertNil(table.bySection["a7"])
        XCTAssertEqual(Set(table.bySection.keys), ["a1", "a2", "a3", "a4", "a5", "a6"])
        let tba = TimetableRatings.build(sections: [section("A 1", "t1", instructors: ["TBA"], TT.meeting("MWF", "0800", "0850"))]) { _, _ in nil }
        XCTAssertEqual(tba.bySection["t1"], TimetableRatings.unratedScore)
    }

    func testScoreWeightsByCreditsAndSkipsUnrated() {
        let a = section("A 1", "a", credits: 4, TT.meeting("M", "0800", "0850"))
        let b = section("B 1", "b", credits: 3, TT.meeting("T", "0800", "0850"))
        let c = section("C 1", "c", credits: 3, TT.meeting("W", "0800", "0850"))
        let d = section("D 1", "d", credits: nil, TT.meeting("R", "0800", "0850"))
        let option = TimetableOption(picks: [a, b, c, d].map { .init(course: $0.courseCode, choice: TimetableChoice(sections: [$0])) },
                                     metrics: TimetableMetrics.of([a, b, c, d]))
        let ratings = TimetableRatings(bySection: ["a": 4.5, "b": 3.0, "d": 1.0]) // c unrated; d has no credits
        let score = ratings.score(option)
        XCTAssertEqual(score?.value ?? 0, (4.5 * 4 + 3.0 * 3) / 7, accuracy: 1e-12)
        XCTAssertEqual(score?.ratedCourses, 2)
        XCTAssertEqual(score?.ratedCredits, 7)
        XCTAssertNil(TimetableRatings.empty.score(option))
        // A linked set counts its first section's credits once, with the first rated section's rating.
        let lecture = section("E 1", "e1", credits: 4, TT.meeting("F", "0800", "0850"))
        let lab = section("E 1", "e2", credits: 0, TT.meeting("F", "1000", "1250"))
        let linked = TimetableOption(picks: [.init(course: "E 1", choice: TimetableChoice(sections: [lecture, lab])), .init(course: "B 1", choice: TimetableChoice(sections: [b]))],
                                     metrics: TimetableMetrics.of([lecture, lab, b]))
        let s2 = TimetableRatings(bySection: ["e2": 5.0, "b": 3.0]).score(linked)
        XCTAssertEqual(s2?.value ?? 0, (5.0 * 4 + 3.0 * 3) / 7, accuracy: 1e-12)
    }

    /// X: x1 (MWF, rated 2.0) or x2 (TR, rated 4.8); Y: y1 (MWF, rated 4.0), y2 (TR, unrated), y3 (MWF, unrated).
    private func courses() -> ([TimetableCourse], TimetableRatings) {
        let x = TT.course("X 1000", [TT.section("X 1000", "x1", "001", TT.meeting("MWF", "0800", "0850")),
                                     TT.section("X 1000", "x2", "002", TT.meeting("TR", "1300", "1415"))])
        let y = TT.course("Y 1000", [TT.section("Y 1000", "y1", "001", TT.meeting("MWF", "0900", "0950")),
                                     TT.section("Y 1000", "y2", "002", TT.meeting("TR", "1700", "1815")),
                                     TT.section("Y 1000", "y3", "003", TT.meeting("MWF", "1100", "1150"))])
        return ([x, y], TimetableRatings(bySection: ["x1": 2.0, "x2": 4.8, "y1": 4.0]))
    }

    func testHighestRatedSortUnscoredLastAndDeterministic() {
        let (c, ratings) = courses()
        let result = TimetableGenerator.generate(courses: c, sort: .highestRated, ratings: ratings)
        let order = result.options.map { $0.crns.joined(separator: "+") }
        // Scores: x2+y1 = 4.4, x2+y2 = x2+y3 = 4.8, x1+y1 = 3.0, x1+y2 = x1+y3 = 2.0. Ties → fewer days, fewer gaps, id.
        XCTAssertEqual(order, ["x2+y2", "x2+y3", "x2+y1", "x1+y1", "x1+y3", "x1+y2"])
        // No ratings at all: every timetable unscored, in fewest-days order, the same on every run.
        let unscored = TimetableGenerator.generate(courses: c, sort: .highestRated, ratings: .empty).options.map(\.id)
        XCTAssertEqual(unscored, TimetableGenerator.generate(courses: c, sort: .highestRated, ratings: .empty).options.map(\.id))
        XCTAssertEqual(result.options.map(\.id), TimetableGenerator.generate(courses: c, sort: .highestRated, ratings: ratings).options.map(\.id))
        XCTAssertEqual(unscored.first, TimetableGenerator.generate(courses: c, sort: .fewestDays).options.first?.id)
        // Partly rated: scored ones first.
        let partial = TimetableGenerator.generate(courses: c, sort: .highestRated, ratings: TimetableRatings(bySection: ["y3": 3.0]))
        XCTAssertEqual(partial.options.prefix(2).map { $0.crns.last }, ["y3", "y3"])
        XCTAssertEqual(TimetableSort.highestRated.label, "Highest professor rating")
        XCTAssertEqual(TimetableSort.allCases.firstIndex(of: .highestRated), TimetableSort.allCases.firstIndex(of: .fewestSessions)! + 1)
    }

    func testCombinedSortsDependOnOrder() {
        let (c, ratings) = courses()
        let daysFirst = TimetableGenerator.generate(courses: c, sorts: [.fewestDays, .highestRated], ratings: ratings).options[0].crns
        let ratingFirst = TimetableGenerator.generate(courses: c, sorts: [.highestRated, .fewestDays], ratings: ratings).options[0].crns
        XCTAssertEqual(daysFirst, ["x2", "y2"])   // the only 2-day timetable
        XCTAssertEqual(ratingFirst, ["x2", "y2"]) // 4.8, and 2 days
        // Earliest finish first vs rating first give different winners.
        let a = TimetableGenerator.generate(courses: c, sorts: [.earliestFinish, .highestRated], ratings: ratings).options.map(\.crns)
        let b = TimetableGenerator.generate(courses: c, sorts: [.highestRated, .earliestFinish], ratings: ratings).options.map(\.crns)
        XCTAssertEqual(a[0], ["x1", "y1"]) // finishes 9:50
        XCTAssertEqual(b[0], ["x2", "y3"]) // 4.8, finishes 2:15 PM (before x2+y2's 6:15 PM)
        XCTAssertNotEqual(a[0], b[0])
        // A single criterion orders exactly like the one-sort API.
        for sort in TimetableSort.allCases where sort != .highestRated {
            XCTAssertEqual(TimetableGenerator.generate(courses: c, sorts: [sort]).options.map(\.id),
                           TimetableGenerator.generate(courses: c, sort: sort).options.map(\.id), sort.rawValue)
        }
        // Duplicates collapse; empty falls back to the default.
        XCTAssertEqual(TimetableSort.normalizedList([.mostSeats, .leastGaps, .mostSeats]), [.mostSeats, .leastGaps])
        XCTAssertEqual(TimetableSort.normalizedList([]), [.fewestDays])
    }

    func testStateDecodesOldAndNewSortFields() throws {
        func state(_ json: String) throws -> TimetableTermState { try JSONDecoder().decode(TimetableTermState.self, from: Data(json.utf8)) }
        XCTAssertEqual(try state(#"{"sort":"leastGaps"}"#).sorts, [.leastGaps])
        XCTAssertEqual(try state(#"{}"#).sorts, [.fewestDays])
        XCTAssertEqual(try state(#"{"sort":"bogus"}"#).sorts, [.fewestDays])
        XCTAssertEqual(try state(#"{"sorts":["mostSeats","bogus","mostSeats","highestRated"],"sort":"leastGaps"}"#).sorts, [.mostSeats, .highestRated])
        XCTAssertEqual(try state(#"{"sorts":[],"sort":"latestStart"}"#).sorts, [.latestStart])
        XCTAssertEqual(try state(#"{"sorts":"nonsense"}"#).sorts, [.fewestDays])
        var s = TimetableTermState(sorts: [.highestRated, .fewestDays, .highestRated])
        XCTAssertEqual(s.sorts, [.highestRated, .fewestDays])
        XCTAssertEqual(s.sort, .highestRated)
        s.sorts = []
        XCTAssertEqual(s.sorts, [.fewestDays])
        s.sort = .mostSeats
        XCTAssertEqual(s.sorts, [.mostSeats])
        s.sorts = [.leastGaps, .highestRated]
        let data = try JSONFile.encoder.encode(s)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""sort" : "leastGaps""#), text) // older builds still read the first criterion
        XCTAssertEqual(try JSONDecoder().decode(TimetableTermState.self, from: data), s)
    }
}
