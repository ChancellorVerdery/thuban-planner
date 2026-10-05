import Foundation
import XCTest
@testable import ThubanPlannerCore

final class DegreeDocumentTests: XCTestCase {
    func load(_ name: String) throws -> (DegreeDocumentText.Extracted, ParsedDegreeDocument) {
        let ex = try DegreeDocumentText.extract(contentsOf: TestSupport.fixtureURL("degree/" + name))
        return (ex, DegreeDocumentParser.parse(ex.text, heading: ex.heading))
    }

    func testCatalogProgramPageHTMLAndMHTML() throws {
        for name in ["bsme-catalog-2025-26.html", "bsme-catalog-2025-26.mhtml"] {
            let (ex, doc) = try load(name)
            XCTAssertEqual(ex.format, name.hasSuffix("mhtml") ? .mhtml : .html)
            XCTAssertEqual(doc.kind, .catalog)
            XCTAssertEqual(doc.programName, "Mechanical Engineering, B.S.M.E.")
            let codes = doc.required.map(\.code)
            XCTAssertEqual(codes.first, "ENGR 1300")
            XCTAssertTrue(codes.contains("PHYS 2101L"))
            XCTAssertTrue(codes.contains("MEGR 3256"))
            XCTAssertEqual(codes.count, 34, name)
            XCTAssertFalse(codes.contains("MEGR 3216"), "the design elective is a choice")
            let mech = try XCTUnwrap(doc.required.first { $0.code == "MEGR 2144" })
            XCTAssertEqual(mech.title, "Introduction to Solid Mechanics")
            XCTAssertEqual(mech.credits, 3)
            XCTAssertEqual(doc.choices.map(\.pick), [2, 1, 4])
            XCTAssertEqual(doc.choices[0].options.map(\.code), ["MATH 1103", "MATH 1241", "MATH 1242"])
            XCTAssertEqual(doc.choices[1].options.map(\.code), ["MEGR 3216", "MEGR 3221"])
            XCTAssertEqual(doc.choices[2].options.count, 68)
            // Prose that mentions courses is skipped, not added.
            XCTAssertTrue(doc.skippedLines.contains { $0.hasPrefix("These courses require a grade of C or better") })
        }
    }

    func testMinorPageWithElectiveSections() throws {
        let (_, doc) = try load("math-minor-2025-26.html")
        XCTAssertEqual(doc.programName, "Mathematics, Minor")
        XCTAssertEqual(doc.required.map(\.code), ["MATH 1241", "MATH 1242"])
        XCTAssertEqual(doc.choices.count, 3)
        XCTAssertEqual(doc.choices[0].options.map(\.code), ["MATH 2164", "MATH 2171", "MATH 2241"])
        XCTAssertEqual(doc.choices[2].label, "Unrestricted Elective Courses (6 credit hours) — Select two of the following:")
        XCTAssertEqual(doc.choices[2].pick, 2)
        XCTAssertTrue(doc.choices[2].options.isEmpty)
        XCTAssertEqual(doc.choices[2].notes.count, 3)
        XCTAssertEqual(doc.choices[1].label, "Restricted Elective Course (3 credit hours)")
        XCTAssertEqual(doc.choices[1].pick, 1)
        XCTAssertTrue(doc.choices[1].notes.contains("MATH 3XXX-4XXX Mathematics Elective"))
    }

    func testPDFWithBrokenLinesAndOptions() throws {
        let (ex, doc) = try load("physics-minor-2025-26.pdf")
        XCTAssertEqual(ex.format, .pdf)
        XCTAssertEqual(doc.programName, "Physics, Minor")
        XCTAssertTrue(doc.required.isEmpty)
        XCTAssertEqual(doc.choices.map(\.label), ["Option 1", "Option 2", "Elective Courses"])
        XCTAssertEqual(doc.choices[0].options.map(\.code), ["PHYS 2101", "PHYS 2101L", "PHYS 2102", "PHYS 2102L", "PHYS 3101", "PHYS 3141"])
        XCTAssertEqual(doc.choices[0].options[0].title, "Physics for Science and Engineering I")
        XCTAssertEqual(doc.choices[0].pick, 6)
        XCTAssertEqual(doc.choices[2].options.count, 20)
    }

    func testDegreeWorksAuditReadsOnlyStillNeeded() throws {
        let (ex, doc) = try load("degreeworks-bsme-redacted.mhtml")
        XCTAssertEqual(ex.format, .mhtml)
        XCTAssertFalse(ex.text.contains("=3D"), "quoted-printable decoded")
        XCTAssertEqual(doc.kind, .degreeWorks)
        XCTAssertEqual(doc.programName, "Bachelor of Science in Mechanical Engineering")
        XCTAssertEqual(doc.required.count, 21)
        XCTAssertEqual(doc.required.first?.code, "ENGR 3295")
        XCTAssertEqual(doc.required.first?.title, "Multidisciplinary Professional Development")
        XCTAssertFalse(doc.required.contains { $0.code == "MEGR 2141" }, "in progress, not still needed")
        XCTAssertEqual(doc.choices.map(\.label), ["Thermal/Fluids Design or Machine Analysis", "Technical Elective"])
        XCTAssertEqual(doc.choices[1].pick, 4)
        XCTAssertEqual(doc.choices[1].options.count, 75)
        XCTAssertEqual(doc.choices[1].notes, ["additionally you need a minimum of 3 Classes in MEGR @"])
    }

    func testChecksheetTextAndDocx() throws {
        for name in ["checksheet-aerospace-minor.txt", "checksheet-aerospace-minor.docx"] {
            let (ex, doc) = try load(name)
            XCTAssertEqual(ex.format, name.hasSuffix("docx") ? .docx : .text)
            XCTAssertEqual(doc.kind, .checksheet)
            XCTAssertEqual(doc.programName, "Minor in Aerospace Engineering")
            XCTAssertEqual(doc.required.map(\.code), ["MEGR 3310", "MEGR 4312", "MEGR 4311"])
            XCTAssertEqual(doc.required[1].prereqGroups, [["MEGR 3111"], ["MEGR 3114"]])
            XCTAssertEqual(doc.required[2].coreqGroups, [["MEGR 3161"]])
            XCTAssertEqual(doc.choices.first?.options.map(\.code), ["MEGR 4310", "MEGR 4313"])
            XCTAssertEqual(doc.skippedLines.count, 1)
        }
    }

    func testTextHelpers() {
        XCTAssertEqual(String(decoding: DegreeDocumentText.quotedPrintable("a=3Db=\r\nc =C3=A9"), as: UTF8.self), "a=bc é")
        XCTAssertEqual(DegreeDocumentText.decodeEntities("A&amp;B&nbsp;&#8211;&#x2192;&bogus;"), "A&B –→&bogus;")
        XCTAssertEqual(DegreeDocumentText.text(fromHTML: "<ul><li>MEGR 2144&nbsp;-&nbsp;Solid</li><li>X</li></ul><script>x</script>"), "• MEGR 2144 - Solid\n\n• X")
        XCTAssertEqual(DegreeDocumentParser.courseLine("MATH 2171 - Differential Equations (3)")?.credits, 3)
        XCTAssertEqual(DegreeDocumentParser.courseLine("MATH 2171  Differential Equations  3")?.title, "Differential Equations")
        XCTAssertNil(DegreeDocumentParser.courseLine("MATH 1103* or MATH 1241*"))
        XCTAssertEqual(DegreeDocumentParser.courseLine("or  MEGR 3221 - Machine Analysis and Design I (3)")?.joiner, "or")
    }
}

final class DegreeImportMergeTests: XCTestCase {
    func parsed(_ name: String) throws -> ParsedDegreeDocument {
        let ex = try DegreeDocumentText.extract(contentsOf: TestSupport.fixtureURL("degree/" + name))
        return DegreeDocumentParser.parse(ex.text, heading: ex.heading)
    }

    func testCatalogPageAddsOnlyWhatIsMissing() throws {
        var data = BSMESampleData.make()
        let before = data.courses
        let plan = DegreeImportMerge.plan(try parsed("bsme-catalog-2025-26.html"), documentName: "bsme.html", data: data)
        XCTAssertEqual(plan.programName, "Mechanical Engineering, B.S.M.E.")
        XCTAssertEqual(plan.requiredCount, 34)
        // PHYS 2101L is satisfied by the plan's PHYS 1101L (a known equivalent).
        XCTAssertTrue(plan.alreadyInPlan.contains(.init(documentCode: "PHYS 2101L", planCode: "PHYS 1101L")))
        XCTAssertEqual(plan.toAdd.map(\.code), [])
        XCTAssertEqual(plan.alreadyInPlan.count, 34)
        // Choices: MATH 1241 + 1242 already satisfy "Two MATH courses"; the design elective too (MEGR 3221).
        XCTAssertTrue(plan.choices[0].isSatisfied)
        XCTAssertTrue(plan.choices[1].isSatisfied)
        XCTAssertEqual(plan.choices[1].inPlan, ["MEGR 3221"])
        // A class counts toward one requirement: MEGR 3221 fills the design elective, so not a technical elective.
        XCTAssertEqual(plan.choices[2].remaining, 4)
        XCTAssertEqual(plan.choices[2].inPlan, [])
        let added = DegreeImportMerge.apply(plan, include: Set(plan.toAdd.map(\.code)), picks: [:], to: &data)
        XCTAssertTrue(added.isEmpty)
        XCTAssertEqual(data.courses, before)
    }

    func testDegreeWorksFillsFromCatalogAndNeverTouchesExisting() throws {
        var data = BSMESampleData.make()
        data.courses.removeAll { ["MEGR 3114", "MEGR 3116", "ENGR 3295"].contains($0.code) }
        let before = data.courses
        let plan = DegreeImportMerge.plan(try parsed("degreeworks-bsme-redacted.mhtml"), documentName: "DegreeWorks.mhtml", data: data)
        XCTAssertEqual(plan.toAdd.map(\.code), ["ENGR 3295", "MEGR 3114", "MEGR 3116"])
        let fluids = try XCTUnwrap(plan.toAdd.first { $0.code == "MEGR 3114" })
        XCTAssertEqual(fluids.title, "Fluid Mechanics")
        XCTAssertEqual(fluids.credits, 3)
        XCTAssertTrue(fluids.filledFromCatalog)
        XCTAssertEqual(fluids.prereqs, ["MATH 2241", "MEGR 3121"])
        let heat = try XCTUnwrap(plan.toAdd.first { $0.code == "MEGR 3116" })
        XCTAssertTrue(heat.coreqs.contains("MEGR 3114"), "an OR-option being added is used")
        // The user unticks ENGR 3295 and picks one technical elective.
        var n = 0
        let added = DegreeImportMerge.apply(plan, include: ["MEGR 3114", "MEGR 3116"], picks: ["choice-2": ["MEGR 3225"]], to: &data) {
            n += 1; return "c-imp-\(n)"
        }
        XCTAssertEqual(added.count, 3)
        XCTAssertEqual(Array(data.courses.prefix(before.count)), before, "existing classes untouched")
        let new = Array(data.courses.dropFirst(before.count))
        XCTAssertEqual(new.map(\.code), ["MEGR 3114", "MEGR 3116", "MEGR 3225"])
        XCTAssertTrue(new.allSatisfy { $0.term == nil && $0.tags == ["program:Bachelor of Science in Mechanical Engineering"] })
        // Idempotent: importing again adds nothing new.
        let again = DegreeImportMerge.plan(try parsed("degreeworks-bsme-redacted.mhtml"), documentName: "DegreeWorks.mhtml", data: data)
        XCTAssertEqual(again.toAdd.map(\.code), ["ENGR 3295"])
        XCTAssertEqual(DegreeImportMerge.apply(again, include: [], picks: ["choice-2": ["MEGR 3225"]], to: &data), [])
    }

    func testMinorMergeWithChoices() throws {
        var data = BSMESampleData.make()
        let plan = DegreeImportMerge.plan(try parsed("math-minor-2025-26.html"), documentName: "math.html", data: data)
        XCTAssertEqual(plan.programTag, "program:Mathematics, Minor")
        XCTAssertTrue(plan.toAdd.isEmpty)
        XCTAssertTrue(plan.choices[0].isSatisfied, "MATH 2171 and 2241 are in the plan")
        XCTAssertEqual(plan.choices[1].available.map(\.code), ["MATH 2164", "MATH 2167", "MATH 2242", "STAT 2122"])
        let ids = DegreeImportMerge.apply(plan, include: [], picks: ["choice-2": ["MATH 2164"]], to: &data)
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(data.courses.last?.code, "MATH 2164")
        XCTAssertEqual(data.courses.last?.title, "Matrices and Linear Algebra")
    }

    func testEmptyDocumentWarns() {
        let doc = DegreeDocumentParser.parse("Hello\nNothing here")
        let plan = DegreeImportMerge.plan(doc, documentName: "x.txt", data: PlannerData())
        XCTAssertEqual(plan.warnings.first, "No course requirements were found in this document.")
    }
}
