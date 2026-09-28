import XCTest
@testable import ThubanPlannerCore

/// The Route board geometry: columns, box sizes / stacking, ribbon ends and curves, hit testing, chains, fit, keyboard
/// neighbours and speed on a big plan.
final class RouteLayoutTests: XCTestCase {
    let m = RouteLayout.Metrics()

    func C(_ id: String, _ credits: Double = 3) -> Course { Course(id: id, code: id.uppercased(), title: "T \(id)", credits: credits) }

    func T(_ key: String, _ kind: TermKind, _ ids: [String]) -> BoardTerm {
        let p = TermKey.parse(key)
        return BoardTerm(key: key, season: p.season ?? .fall, year: p.year, current: kind == .current, kind: kind,
                         courseIds: ids, credits: 0)
    }

    func testEmptyScheduleIsEmptyLayout() {
        let layout = RouteLayout.make(schedule: .empty, courses: [])
        XCTAssertTrue(layout.isEmpty)
        XCTAssertEqual(layout.size, .zero)
        XCTAssertNil(layout.box(at: CGPoint(x: 50, y: 50)))
        XCTAssertEqual(layout.fitScale(in: CGSize(width: 800, height: 600)), 1)
    }

    func testEmptyTermsAreNotColumns() {
        let s = Schedule(board: [T("spring-2025", .past, []), T("fall-2025", .current, ["a"])])
        let layout = RouteLayout.make(schedule: s, courses: [C("a")])
        XCTAssertEqual(layout.columns.map(\.term.key), ["fall-2025"])
        XCTAssertEqual(layout.box("a")?.columnIndex, 0)
    }

    func testBoxesStackWithHeightProportionalToCredits() {
        let s = Schedule(board: [T("fall-2025", .current, ["a", "b", "c", "z"])])
        let layout = RouteLayout.make(schedule: s, courses: [C("a", 3), C("b", 1), C("c", 4.5)])
        let a = layout.box("a")!.rect, b = layout.box("b")!.rect, c = layout.box("c")!.rect
        XCTAssertEqual(a.minX, m.padding + m.boxInset)
        XCTAssertEqual(a.minY, m.padding + m.headerHeight)
        XCTAssertEqual(a.height, 72)
        XCTAssertEqual(b.height, m.minBoxHeight, "1 credit is below the minimum height")
        XCTAssertEqual(c.height, 108)
        XCTAssertEqual(b.minY, a.maxY + m.boxGap)
        XCTAssertEqual(c.minY, b.maxY + m.boxGap)
        XCTAssertEqual(a.width, m.columnWidth - 2 * m.boxInset)
        XCTAssertNil(layout.box("z"), "an id that names no class is skipped")
        XCTAssertEqual(layout.boxes.count, 3)
    }

    func testZeroAndHostileCreditsUseTheMinimumHeight() {
        XCTAssertEqual(m.boxHeight(credits: 0), m.minBoxHeight)
        XCTAssertEqual(m.boxHeight(credits: -.infinity), m.minBoxHeight)
        XCTAssertEqual(m.boxHeight(credits: .nan), m.minBoxHeight)
    }

    func testColumnsShareOneHeightAndBoardSize() {
        let s = Schedule(board: [T("fall-2025", .past, ["a"]), T("spring-2026", .current, ["b", "c"]), T("fall-2026", .future, ["d"])])
        let layout = RouteLayout.make(schedule: s, courses: ["a", "b", "c", "d"].map { C($0) })
        XCTAssertEqual(Set(layout.columns.map(\.frame.height)).count, 1)
        XCTAssertEqual(layout.columns[1].frame.minX, m.padding + m.columnPitch)
        let tallest = layout.box("c")!.rect.maxY
        XCTAssertEqual(layout.columns[0].frame.maxY, tallest + m.bottomInset)
        XCTAssertEqual(layout.size.width, 2 * m.padding + 3 * m.columnWidth + 2 * m.gutter)
        XCTAssertEqual(layout.size.height, tallest + m.bottomInset + m.padding)
        XCTAssertEqual(layout.boxes.map(\.kind), [.past, .current, .current, .future])
    }

    func testDuplicateIdKeepsItsLastBox() {
        let s = Schedule(board: [T("fall-2025", .past, ["a"]), T("spring-2026", .current, ["a"])])
        let layout = RouteLayout.make(schedule: s, courses: [C("a")])
        XCTAssertEqual(layout.boxes.count, 1)
        XCTAssertEqual(layout.box("a")?.columnIndex, 1)
    }

    func testRibbonIsAtlasBezierBetweenColumns() {
        let s = Schedule(board: [T("fall-2025", .past, ["a"]), T("spring-2026", .future, ["x", "b"])],
                         edges: [RouteEdge(from: "a", to: "b", kind: .prereq), RouteEdge(from: "a", to: "gone", kind: .prereq)])
        let layout = RouteLayout.make(schedule: s, courses: [C("a"), C("x"), C("b")])
        XCTAssertEqual(layout.ribbons.count, 1, "edges to classes not on the board are skipped")
        let r = layout.ribbons[0], a = layout.box("a")!.rect, b = layout.box("b")!.rect
        XCTAssertFalse(r.sameColumn)
        XCTAssertEqual(r.start, CGPoint(x: a.maxX, y: a.midY))
        XCTAssertEqual(r.end, CGPoint(x: b.minX, y: b.midY))
        let mx = (a.maxX + b.minX) / 2
        XCTAssertEqual(r.control1, CGPoint(x: mx, y: a.midY))
        XCTAssertEqual(r.control2, CGPoint(x: mx, y: b.midY))
        XCTAssertEqual(r.edgeIndex, 0)
    }

    func testSeveralRibbonEndsSpreadAcrossTheBoxInOrder() {
        let s = Schedule(board: [T("fall-2025", .past, ["a"]), T("spring-2026", .future, ["b", "c", "d"])],
                         edges: [RouteEdge(from: "a", to: "d", kind: .prereq), RouteEdge(from: "a", to: "b", kind: .prereq),
                                 RouteEdge(from: "a", to: "c", kind: .coreq)])
        let layout = RouteLayout.make(schedule: s, courses: ["a", "b", "c", "d"].map { C($0) })
        let a = layout.box("a")!.rect
        let starts = layout.ribbons.map(\.start.y)
        let band = a.height * m.portBand
        XCTAssertEqual(starts[1], a.midY - band / 2, accuracy: 0.001, "the ribbon to the top box leaves highest")
        XCTAssertEqual(starts[2], a.midY, accuracy: 0.001)
        XCTAssertEqual(starts[0], a.midY + band / 2, accuracy: 0.001)
        for r in layout.ribbons {
            XCTAssertEqual(r.end.y, layout.box(r.to)!.rect.midY, "single incoming ribbons meet the middle")
            XCTAssertTrue(a.minY...a.maxY ~= r.start.y)
        }
    }

    func testDuplicateEdgesShareASlot() {
        let s = Schedule(board: [T("fall-2025", .past, ["a"]), T("spring-2026", .future, ["b"])],
                         edges: [RouteEdge(from: "a", to: "b", kind: .prereq), RouteEdge(from: "a", to: "b", kind: .prereq)])
        let layout = RouteLayout.make(schedule: s, courses: [C("a"), C("b")])
        XCTAssertEqual(layout.ribbons.count, 2)
        XCTAssertEqual(layout.ribbons[0].start, layout.ribbons[1].start)
        XCTAssertEqual(layout.ribbons[0].start.y, layout.box("a")!.rect.midY)
    }

    func testSameColumnCoreqIsABracketOnTheRight() {
        let s = Schedule(board: [T("fall-2025", .current, ["lec", "lab"])],
                         edges: [RouteEdge(from: "lab", to: "lec", kind: .coreq)])
        let layout = RouteLayout.make(schedule: s, courses: [C("lec"), C("lab", 1)])
        let r = layout.ribbons[0], lec = layout.box("lec")!.rect, lab = layout.box("lab")!.rect
        XCTAssertTrue(r.sameColumn)
        XCTAssertEqual(r.start, CGPoint(x: lab.maxX, y: lab.midY))
        XCTAssertEqual(r.end, CGPoint(x: lec.maxX, y: lec.midY))
        XCTAssertGreaterThan(r.control1.x, lab.maxX)
        XCTAssertEqual(r.control1.x, r.control2.x)
        XCTAssertLessThan(r.control1.x, layout.columns[0].frame.maxX + m.gutter, "the bracket stays in the gutter")
    }

    func testRibbonSkippingColumnsRunsThroughGapsNotBoxes() {
        let s = Schedule(board: [T("fall-2024", .past, ["a"]), T("spring-2025", .past, ["m1", "m2", "m3"]),
                                 T("fall-2025", .past, ["n1", "n2"]), T("spring-2026", .future, ["b"])],
                         edges: [RouteEdge(from: "a", to: "b", kind: .prereq), RouteEdge(from: "m1", to: "n1", kind: .prereq)])
        let layout = RouteLayout.make(schedule: s, courses: ["a", "m1", "m2", "m3", "n1", "n2", "b"].map { C($0) })
        let long = layout.ribbons[0], short = layout.ribbons[1]
        XCTAssertTrue(short.waypoints.isEmpty, "a ribbon between neighbouring columns is one curve")
        XCTAssertEqual(long.waypoints.count, 4, "an entry and an exit per crossed column")
        for pair in stride(from: 0, to: long.waypoints.count, by: 2) {
            let entry = long.waypoints[pair], exit = long.waypoints[pair + 1]
            XCTAssertEqual(entry.y, exit.y)
            let run = CGRect(x: entry.x, y: entry.y - 1, width: exit.x - entry.x, height: 2)
            for box in layout.boxes where box.courseId != "a" && box.courseId != "b" {
                XCTAssertFalse(run.intersects(box.rect), "the lane misses \(box.courseId)")
            }
        }
        let segs = long.segments
        XCTAssertEqual(segs.count, 5)
        XCTAssertEqual(segs.first!.start, long.start)
        XCTAssertEqual(segs.last!.end, long.end)
        for (x, y) in zip(segs, segs.dropFirst()) { XCTAssertEqual(x.end, y.start) }
    }

    func testHitTesting() {
        let s = Schedule(board: [T("fall-2025", .past, ["a", "b"]), T("spring-2026", .future, ["c"])])
        let layout = RouteLayout.make(schedule: s, courses: [C("a"), C("b"), C("c")])
        let b = layout.box("b")!.rect, c = layout.box("c")!.rect
        XCTAssertEqual(layout.box(at: CGPoint(x: b.midX, y: b.midY))?.courseId, "b")
        XCTAssertEqual(layout.box(at: CGPoint(x: c.minX + 1, y: c.minY + 1))?.courseId, "c")
        XCTAssertNil(layout.box(at: CGPoint(x: b.midX, y: b.minY - m.boxGap / 2)), "the gap between boxes")
        XCTAssertNil(layout.box(at: CGPoint(x: b.maxX + m.gutter / 2, y: b.midY)), "the gutter")
        XCTAssertNil(layout.box(at: CGPoint(x: -5, y: b.midY)))
        XCTAssertEqual(layout.column(at: CGPoint(x: c.midX, y: m.padding + 4))?.term.key, "spring-2026")
    }

    func testChainFollowsRequirementsBothWaysTransitively() {
        // a → b → d, c → d, d → e; x unrelated; f → a (upstream of a).
        let s = Schedule(board: [T("fall-2024", .past, ["f"]), T("fall-2025", .past, ["a", "c", "x"]),
                                 T("spring-2026", .current, ["b"]), T("fall-2026", .future, ["d"]), T("spring-2027", .future, ["e"])],
                         edges: [RouteEdge(from: "a", to: "b", kind: .prereq), RouteEdge(from: "b", to: "d", kind: .prereq),
                                 RouteEdge(from: "c", to: "d", kind: .coreq), RouteEdge(from: "d", to: "e", kind: .prereq),
                                 RouteEdge(from: "f", to: "a", kind: .prereq)])
        let layout = RouteLayout.make(schedule: s, courses: ["a", "b", "c", "d", "e", "f", "x"].map { C($0) })
        let chain = layout.chain(of: "b")
        XCTAssertEqual(chain.courseIds, ["f", "a", "b", "d", "e"], "c is a sibling requirement of d, not on b's chain")
        XCTAssertEqual(chain.ribbons, [0, 1, 3, 4])
        XCTAssertEqual(layout.chain(of: "x").courseIds, ["x"])
        XCTAssertEqual(layout.chain(of: "x").ribbons, [])
        XCTAssertEqual(layout.chain(of: "nope").courseIds, [])
    }

    func testChainIsCycleSafe() {
        let s = Schedule(board: [T("fall-2025", .current, ["lec", "lab"])],
                         edges: [RouteEdge(from: "lab", to: "lec", kind: .coreq), RouteEdge(from: "lec", to: "lab", kind: .coreq)])
        let layout = RouteLayout.make(schedule: s, courses: [C("lec"), C("lab", 1)])
        XCTAssertEqual(layout.chain(of: "lec").courseIds, ["lec", "lab"])
        XCTAssertEqual(layout.chain(of: "lec").ribbons, [0, 1])
    }

    func testFitScale() {
        let s = Schedule(board: (0..<8).map { T("fall-\(2020 + $0)", .future, ["c\($0)"]) })
        let layout = RouteLayout.make(schedule: s, courses: (0..<8).map { C("c\($0)") })
        let viewport = CGSize(width: layout.size.width / 2, height: 2000)
        XCTAssertEqual(layout.fitScale(in: viewport), 0.5, accuracy: 0.0001)
        XCTAssertEqual(layout.fitScale(in: CGSize(width: 10_000, height: 10_000)), 1, "small boards are not blown up")
        XCTAssertEqual(layout.fitScale(in: CGSize(width: 10_000, height: 10_000), maxScale: 2), 2)
    }

    func testKeyboardNeighbours() {
        let s = Schedule(board: [T("fall-2025", .past, ["a", "b", "c"]), T("spring-2026", .current, []),
                                 T("fall-2026", .future, ["d", "e"])])
        let layout = RouteLayout.make(schedule: s, courses: [C("a"), C("b"), C("c", 1), C("d", 6), C("e")])
        XCTAssertEqual(layout.neighbor(of: "a", .down), "b")
        XCTAssertEqual(layout.neighbor(of: "a", .up), nil)
        XCTAssertEqual(layout.neighbor(of: "c", .down), nil)
        XCTAssertEqual(layout.neighbor(of: "b", .right), "d", "nearest by vertical centre; the empty term is not a column")
        XCTAssertEqual(layout.neighbor(of: "e", .left), "c")
        XCTAssertEqual(layout.neighbor(of: "e", .right), nil)
    }

    func testSampleDegreeLaysOutEveryPlacedClass() {
        let data = SampleData.make(now: TestSupport.date("2026-10-01"), calendar: TestSupport.utc)
        let schedule = Scheduler.scheduleDegree(data, now: TestSupport.date("2026-10-01"), calendar: TestSupport.utc)
        let layout = RouteLayout.make(schedule: schedule, courses: data.courses)
        let placed = Set(schedule.columns.flatMap(\.courseIds))
        XCTAssertEqual(Set(layout.boxes.map(\.courseId)), placed)
        XCTAssertEqual(layout.ribbons.count, schedule.edges.count)
        for r in layout.ribbons where !r.sameColumn {
            XCTAssertLessThan(r.start.x, r.end.x, "prerequisites flow left to right")
        }
        // No two boxes overlap.
        for (i, a) in layout.boxes.enumerated() {
            for b in layout.boxes[(i + 1)...] { XCTAssertFalse(a.rect.intersects(b.rect), "\(a.courseId) / \(b.courseId)") }
        }
    }

    func testBigPlanIsFast() {
        // 120 classes, 12 columns, a dense requirement web.
        var courses: [Course] = []
        var board: [BoardTerm] = []
        var edges: [RouteEdge] = []
        for t in 0..<12 {
            var ids: [String] = []
            for k in 0..<10 {
                let id = "c\(t)-\(k)"
                courses.append(C(id, Double(1 + (k % 4))))
                ids.append(id)
                if t > 0 {
                    edges.append(RouteEdge(from: "c\(t - 1)-\(k)", to: id, kind: .prereq))
                    edges.append(RouteEdge(from: "c\(t - 1)-\((k + 3) % 10)", to: id, kind: k % 2 == 0 ? .prereq : .coreq))
                }
            }
            board.append(T("fall-\(2020 + t)", t < 4 ? .past : .future, ids))
        }
        let schedule = Schedule(board: board, edges: edges)
        measure {
            let layout = RouteLayout.make(schedule: schedule, courses: courses)
            _ = layout.chain(of: "c6-4")
            _ = layout.box(at: CGPoint(x: 900, y: 300))
        }
        let layout = RouteLayout.make(schedule: schedule, courses: courses)
        XCTAssertEqual(layout.boxes.count, 120)
        XCTAssertEqual(layout.ribbons.count, edges.count)
        let chain = layout.chain(of: "c0-0")
        XCTAssertTrue(chain.courseIds.isSuperset(of: ["c0-0", "c1-0", "c1-7", "c11-0"]))
        XCTAssertFalse(chain.courseIds.contains("c0-1"), "a sibling in the first term is not on the chain")
    }
}
