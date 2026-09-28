import Foundation
import ThubanPlannerCore

/// Extra Route smoke screens (the standard walk already captures `11-route` and `71-route-dark`). OWNER: Engineer B.
extension SmokeScenes {
    static var route: [SmokeScene] {
        [
            // Fluid Mechanics selected: its requirement chain is emphasized, the rest dims.
            SmokeScene(name: "route-chain") { app in
                app.section = .route
                app.selectedCourseId = "c-sample-31"
            } cleanup: { app in app.selectedCourseId = nil },
            SmokeScene(name: "route-chain-dark") { app in
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                app.section = .route
                app.selectedCourseId = "c-sample-37"
            } cleanup: { app in
                app.selectedCourseId = nil
                app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            },
            SmokeScene(name: "route-zoomed") { app in
                app.section = .route
                app.routeZoom = 2
            } cleanup: { app in app.routeZoom = 1; app.routeFitRequest += 1 },
            // A prerequisite cycle: two classes can't be placed → warning banner + the unplaceable strip.
            SmokeScene(name: "route-unplaceable") { app in
                app.section = .route
                app.mutate { data in
                    data.addCourse(code: "MEGR 4990", title: "Capstone Seminar", credits: 3, prereqs: ["MEGR 4991"])
                    data.addCourse(code: "MEGR 4991", title: "Capstone Studio", credits: 3, prereqs: ["MEGR 4990"])
                }
            } cleanup: { app in app.replaceData(SampleData.make(now: app.now, calendar: app.calendar)) },
            // 72 classes over 12 terms with a dense requirement web (speed + legibility at fit).
            SmokeScene(name: "route-dense", settle: 1.6) { app in
                app.section = .route
                app.replaceData(routeDensePlan(now: app.now, calendar: app.calendar))
            } cleanup: { app in app.replaceData(SampleData.make(now: app.now, calendar: app.calendar)) },
            SmokeScene(name: "route-dense-dark", settle: 1.6) { app in
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                app.section = .route
                app.replaceData(routeDensePlan(now: app.now, calendar: app.calendar))
                app.selectedCourseId = "c-dense-40"
            } cleanup: { app in
                app.selectedCourseId = nil
                app.replaceData(SampleData.make(now: app.now, calendar: app.calendar))
                app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            },
            SmokeScene(name: "route-empty") { app in
                app.section = .route
                app.replaceData(.empty)
            } cleanup: { app in app.replaceData(SampleData.make(now: app.now, calendar: app.calendar)) },
            SmokeScene(name: "route-empty-dark") { app in
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                app.section = .route
                app.replaceData(.empty)
            } cleanup: { app in
                app.replaceData(SampleData.make(now: app.now, calendar: app.calendar))
                app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            },
        ]
    }
}

/// A big synthetic plan for the dense smoke scenes: 3 recorded past terms + current (24 classes taken) and 48 to
/// take with chained prerequisites and lecture / lab corequisites.
@MainActor
func routeDensePlan(now: Date, calendar: Calendar) -> PlannerData {
    let current = TermKey.current(now: now, calendar: calendar)
    var keys = [current]
    while keys.count < 4 {
        var k = TermKey.previous(keys[0])
        while TermKey.season(k) == .summer { k = TermKey.previous(k) }
        keys.insert(k, at: 0)
    }
    let terms = keys.enumerated().map { i, key -> Term in
        let p = TermKey.parse(key)
        return Term(season: p.season ?? .fall, year: p.year, current: i == keys.count - 1)
    }
    let subjects = ["MATH", "PHYS", "MEGR", "ECGR", "CHEM", "STAT"]
    let titles = ["Foundations", "Analysis", "Systems", "Design Studio", "Methods", "Laboratory Practice",
                  "Advanced Topics in Modelling", "Seminar", "Applications", "Theory"]
    var courses: [Course] = []
    for i in 0..<72 {
        let subject = subjects[i % subjects.count]
        let code = "\(subject) \(1000 + (i / 6) * 100 + i % 6 * 7)"
        let credits: Double = i % 9 == 4 ? 1 : (i % 7 == 3 ? 4 : 3)
        var pre: [String] = []
        var co: [String] = []
        if i >= 6 { pre.append(courses[i - 6].code) }
        if i >= 13, i % 3 == 0 { pre.append(courses[i - 13].code) }
        if i % 9 == 4, i > 0 { co.append(courses[i - 1].code) }
        let term: String? = i < 24 ? keys[i / 6] : nil
        courses.append(Course(id: String(format: "c-dense-%02d", i), code: code, title: "\(subject.capitalized) \(titles[i % titles.count])",
                              credits: credits, prereqs: pre, coreqs: co, summerOk: i % 4 == 0, term: term))
    }
    return PlannerData(courses: courses, terms: terms, disabledTerms: [],
                       settings: PlannerSettings(maxCredits: 16, summerMax: 7, strategy: .soonestSummer))
}
