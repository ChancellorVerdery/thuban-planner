import Foundation
import ThubanPlannerCore

/// Class detail sheet smoke screens (window: .sheet). OWNER: Engineer B.
extension SmokeScenes {
    static var classDetail: [SmokeScene] {
        [
            // Planned class with two resolved prerequisites and dependents.
            SmokeScene(name: "class-detail", window: .sheet) { app in
                app.section = .route
                app.presentCourse("c-sample-31")
            } cleanup: { app in app.presentedCourseId = nil },
            SmokeScene(name: "class-detail-dark", window: .sheet) { app in
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                app.section = .route
                app.presentCourse("c-sample-33")
            } cleanup: { app in
                app.presentedCourseId = nil
                app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            },
            // A taken class with a lecture / lab corequisite loop.
            SmokeScene(name: "class-detail-taken", window: .sheet) { app in
                app.section = .planner
                app.presentCourse("c-sample-14")
            } cleanup: { app in app.presentedCourseId = nil },
            // A transfer-credit class (STAT 3128, required by ENGR 3295).
            SmokeScene(name: "class-detail-transfer", window: .sheet) { app in
                app.section = .planner
                app.replaceData(SampleData.makeWithTransferCredit(now: app.now, calendar: app.calendar))
                app.presentCourse("c-sample-t1")
            } cleanup: { app in
                app.presentedCourseId = nil
                app.replaceData(SampleData.make(now: app.now, calendar: app.calendar))
            },
            // A requirement that names no class in the plan ("not in your plan"), no dependents.
            SmokeScene(name: "class-detail-unknown-ref", window: .sheet) { app in
                app.section = .route
                app.presentCourse("c-sample-41")   // ENGR 3295 needs STAT 3128
            } cleanup: { app in app.presentedCourseId = nil },
            // A class in a prerequisite cycle: "Can't place".
            SmokeScene(name: "class-detail-unplaceable", window: .sheet) { app in
                app.section = .route
                app.mutate { data in
                    data.addCourse(code: "MEGR 4990", title: "Capstone Seminar", credits: 3, prereqs: ["MEGR 4991"])
                    data.addCourse(code: "MEGR 4991", title: "Capstone Studio", credits: 3, prereqs: ["MEGR 4990"])
                }
                if let id = app.courses.first(where: { $0.code == "MEGR 4990" })?.id { app.presentCourse(id) }
            } cleanup: { app in
                app.presentedCourseId = nil
                app.replaceData(SampleData.make(now: app.now, calendar: app.calendar))
            },
        ]
    }
}
