import AppKit
import Foundation
import ThubanPlannerCore

/// Smoke scenes for Technical electives and Import degree requirements (offline: the bundled catalog dataset and
/// offerings snapshot, `BSMESampleData`). Registered from `SmokeScenes.planner`.
extension SmokeScenes {
    static var electives: [SmokeScene] {
        [
            SmokeScene(name: "electives-panel", window: .sheet, settle: 1.4) { app in
                electivesSmokeStart(app)
                app.degreeTools.openElectives()
            } cleanup: { app in electivesSmokeEnd(app) },
            SmokeScene(name: "electives-panel-dark", window: .sheet, settle: 1.4) { app in
                electivesSmokeStart(app)
                electivesSmokeTheme(app, dark: true)
                app.degreeTools.openElectives()
            } cleanup: { app in
                electivesSmokeEnd(app)
                electivesSmokeTheme(app, dark: false)
            },
            SmokeScene(name: "electives-show-not-offered", window: .sheet, settle: 1.4) { app in
                electivesSmokeStart(app)
                app.degreeTools.openElectives()
                app.degreeTools.showNotOffered = true
                app.degreeTools.filter = .megr
                app.degreeTools.search = "32"
            } cleanup: { app in electivesSmokeEnd(app) },
            // The user's example: Quantum Mechanics II needs Quantum I, which needs Modern Physics.
            SmokeScene(name: "electives-add-chain", window: .sheet, settle: 1.4) { app in
                electivesSmokeStart(app)
                app.degreeTools.openElectives()
                app.degreeTools.choose("PHYS 4242")
            } cleanup: { app in electivesSmokeEnd(app) },
            SmokeScene(name: "electives-add-chain-dark", window: .sheet, settle: 1.4) { app in
                electivesSmokeStart(app)
                electivesSmokeTheme(app, dark: true)
                app.degreeTools.openElectives()
                app.degreeTools.choose("PHYS 4242")
            } cleanup: { app in
                electivesSmokeEnd(app)
                electivesSmokeTheme(app, dark: false)
            },
            // OR-groups the plan doesn't satisfy become pickers.
            SmokeScene(name: "electives-choice-picker", window: .sheet, settle: 1.4) { app in
                var data = BSMESampleData.make()
                data.courses.removeAll { ["MATH 2241", "MEGR 2144", "MATH 2171", "MEGR 2141"].contains($0.code) }
                electivesSmokeStart(app, data: data)
                app.degreeTools.openElectives()
                app.degreeTools.choose("PHYS 4242")
                app.degreeTools.setChoice("PHYS 4241#p0", "PHYS 3220")
            } cleanup: { app in electivesSmokeEnd(app) },
            SmokeScene(name: "electives-added", window: .sheet, settle: 1.4) { app in
                electivesSmokeStart(app)
                app.degreeTools.openElectives()
                app.degreeTools.choose("MEGR 3225")
                app.degreeTools.choose("PHYS 4242")
                app.degreeTools.confirmAdd()
            } cleanup: { app in electivesSmokeEnd(app) },
            SmokeScene(name: "electives-remove", window: .sheet, settle: 1.4) { app in
                electivesSmokeStart(app)
                app.degreeTools.openElectives()
                app.degreeTools.choose("PHYS 4242")
                app.degreeTools.confirmAdd()
                app.degreeTools.beginRemove("PHYS 4242")
            } cleanup: { app in electivesSmokeEnd(app) },
            // The Planner after choosing electives: "Tech electives 2/4" and the TE marks in the table.
            SmokeScene(name: "planner-tech-electives", settle: 1.4) { app in
                electivesSmokeStart(app)
                app.degreeTools.openElectives()
                app.degreeTools.choose("MEGR 3225")
                app.degreeTools.choose("PHYS 4242")
                app.degreeTools.confirmAdd()
                app.degreeTools.closeSheet()
                PlannerViewState.shared.search = "phys 4"
            } cleanup: { app in
                PlannerViewState.shared.reset()
                electivesSmokeEnd(app)
            },
            SmokeScene(name: "degree-import-choose", window: .sheet, settle: 1.2) { app in
                electivesSmokeStart(app)
                app.degreeTools.openImport()
            } cleanup: { app in electivesSmokeEnd(app) },
            SmokeScene(name: "degree-import-preview", window: .sheet, settle: 1.4) { app in
                electivesSmokeStart(app)
                app.degreeTools.openImport()
                app.degreeTools.preview(DegreeDocumentParser.parse(electivesSmokeMathMinor, heading: "Mathematics, Minor"),
                                        fileName: "Mathematics, Minor.pdf", format: .pdf)
                app.degreeTools.togglePick("choice-2", "MATH 2164")
            } cleanup: { app in electivesSmokeEnd(app) },
            SmokeScene(name: "degree-import-preview-degreeworks", window: .sheet, settle: 1.4) { app in
                var data = BSMESampleData.make()
                data.courses.removeAll { ["MEGR 3114", "MEGR 3116", "ENGR 3295", "MEGR 3251"].contains($0.code) }
                electivesSmokeStart(app, data: data)
                app.degreeTools.openImport()
                app.degreeTools.preview(DegreeDocumentParser.parse(electivesSmokeDegreeWorks), fileName: "DegreeWorks _ UNC Charlotte.mhtml", format: .mhtml)
            } cleanup: { app in electivesSmokeEnd(app) },
            SmokeScene(name: "degree-import-preview-dark", window: .sheet, settle: 1.4) { app in
                electivesSmokeStart(app)
                electivesSmokeTheme(app, dark: true)
                app.degreeTools.openImport()
                app.degreeTools.preview(DegreeDocumentParser.parse(electivesSmokeMathMinor, heading: "Mathematics, Minor"),
                                        fileName: "Mathematics, Minor.pdf", format: .pdf)
                app.degreeTools.togglePick("choice-2", "MATH 2164")
            } cleanup: { app in
                electivesSmokeEnd(app)
                electivesSmokeTheme(app, dark: false)
            },
            SmokeScene(name: "degree-import-result", window: .sheet, settle: 1.4) { app in
                var data = BSMESampleData.make()
                data.courses.removeAll { ["MEGR 3114", "MEGR 3116", "ENGR 3295", "MEGR 3251"].contains($0.code) }
                electivesSmokeStart(app, data: data)
                app.degreeTools.openImport()
                app.degreeTools.preview(DegreeDocumentParser.parse(electivesSmokeDegreeWorks), fileName: "DegreeWorks _ UNC Charlotte.mhtml", format: .mhtml)
                app.degreeTools.applyImport()
            } cleanup: { app in electivesSmokeEnd(app) },
        ]
    }
}

@MainActor private func electivesSmokeStart(_ app: AppModel, data: PlannerData = BSMESampleData.make()) {
    app.section = .planner
    PlannerViewState.shared.reset()
    app.degreeTools.closeSheet()
    app.degreeTools.resetImport()
    app.degreeTools.search = ""
    app.degreeTools.filter = .all
    app.degreeTools.showNotOffered = false
    app.replaceData(data)
}

@MainActor private func electivesSmokeEnd(_ app: AppModel) {
    app.degreeTools.closeSheet()
    app.degreeTools.resetImport()
    app.degreeTools.lastAdd = nil
    app.degreeTools.search = ""
    app.degreeTools.filter = .all
    app.degreeTools.showNotOffered = false
    app.replaceData(SampleData.make(now: app.now, calendar: app.calendar))
}

@MainActor private func electivesSmokeTheme(_ app: AppModel, dark: Bool) {
    app.setThemeSelection(ThemeSelection(mode: dark ? .dark : .light, schemeId: SchemePresets.defaultId, custom: nil))
}

/// The Mathematics minor as UNC Charlotte's 2025-26 catalog lists it (text of the program page).
private let electivesSmokeMathMinor = """
Mathematics, Minor
Minor Requirements
A Minor in Mathematics requires 18 credit hours.
Required Courses (9 credit hours)
• MATH 1241 - Calculus I (3)
• MATH 1242 - Calculus II (3)
• MATH 2164 - Matrices and Linear Algebra (3)
• or MATH 2171 - Differential Equations (3)
• or MATH 2241 - Calculus III (3)
Restricted Elective Course (3 credit hours)
• MATH 2164 - Matrices and Linear Algebra (3)
• MATH 2167 - Introduction to Mathematical Reasoning (3)
• MATH 2171 - Differential Equations (3)
• MATH 2241 - Calculus III (3)
• MATH 2242 - Calculus IV (3)
• STAT 2122 - Introduction to Probability and Statistics (3)
• MATH 3XXX-4XXX Mathematics Elective (3)
Unrestricted Elective Courses (6 credit hours)
Select two of the following:
• MATH 3XXX-4XXX Mathematics Elective (3)
• STAT 3XXX-4XXX Statistics Elective (3)
Note: Typically, a focus on pure math requires MATH 2164 and MATH 2167.
Total = 18 Credit Hours
"""

/// A DegreeWorks audit's major block, as its saved page reads (fictional student; codes and labels as UNC Charlotte
/// prints them).
private let electivesSmokeDegreeWorks = """
DegreeWorks | UNC Charlotte
Degree progress
Audit date 10/05/2026
Major in Mechanical Engineering
Multidisciplinary Professional Development Not complete Multidisciplinary Professional Development
Still needed:
1 Class in ENGR 3295
Fluid Mechanics Not complete Fluid Mechanics
Still needed:
1 Class in MEGR 3114
Introduction to Heat Transfer Not complete Introduction to Heat Transfer
Still needed:
1 Class in MEGR 3116
Thermal/Fluids Design or Machine Analysis Not complete Thermal/Fluids Design or Machine Analysis
Still needed:
1 Class in MEGR 3216
or 3221
Thermals/Fluids Lab Not complete Thermals/Fluids Lab
Still needed:
1 Class in MEGR 3251
Senior Design II Not complete Senior Design II
Still needed:
1 Class in MEGR 3256
Technical Elective Not complete
Technical Elective
Still needed:
4 Classes in MEGR 3090
or 3225
or 3282
or 4242
or 4312
or PHYS 3220
or 4242
additionally you need a minimum of 3 Classes in MEGR @
"""
