import Foundation
import ThubanPlannerCore

/// Schedule smoke scenes (offline: sample terms and sections seeded by `ScheduleModel.seedOfflineSample`).
extension SmokeScenes {
    static var schedule: [SmokeScene] {
        [
            SmokeScene(name: "schedule-route") { app in
                app.section = .schedule
                app.scheduleTab.smokeSet(auth: .signedOut) { $0.source = .route; $0.selectedIndex = 0 }
            },
            SmokeScene(name: "schedule-expanded-course") { app in
                app.section = .schedule
                app.scheduleTab.smokeSet(auth: .signedIn(name: "Sample Student")) { $0.source = .route; $0.selectedIndex = 2 }
                app.scheduleTab.expandedCourse = app.scheduleTab.rows.first?.code
            } cleanup: { app in
                app.scheduleTab.expandedCourse = nil
                app.scheduleTab.smokeSet { $0.selectedIndex = 0 }
            },
            SmokeScene(name: "schedule-block-times") { app in
                app.section = .schedule
                app.scheduleTab.smokeSet(blockMode: true) { s in
                    s.blocks = [TimetableBlock(id: "smoke-1", day: .monday, start: 12 * 60, end: 13 * 60 + 30, label: "Work"),
                                TimetableBlock(id: "smoke-2", day: .wednesday, start: 12 * 60, end: 13 * 60 + 30, label: "Work"),
                                TimetableBlock(id: "smoke-3", day: .friday, start: 7 * 60, end: 10 * 60, label: "Gym"),
                                TimetableBlock(id: "smoke-4", day: .tuesday, start: 17 * 60, end: 20 * 60, label: "")]
                }
            } cleanup: { app in
                app.scheduleTab.smokeSet(blockMode: false)
            },
            SmokeScene(name: "schedule-with-blocks") { app in
                app.section = .schedule
                app.scheduleTab.smokeSet(blockMode: false)
            } cleanup: { app in
                app.scheduleTab.smokeSet { $0.blocks = [] }
            },
            SmokeScene(name: "schedule-zero-schedules") { app in
                app.section = .schedule
                app.scheduleTab.smokeSet { s in
                    s.filters = TimetableFilters(openSeatsOnly: true)
                    s.blocks = (1...5).compactMap { BannerWeekday(rawValue: $0) }.map {
                        TimetableBlock(id: "z\($0.rawValue)", day: $0, start: 8 * 60, end: 12 * 60 + 30, label: "Work")
                    }
                }
            } cleanup: { app in
                app.scheduleTab.smokeSet { $0.filters = TimetableFilters(); $0.blocks = [] }
            },
            SmokeScene(name: "schedule-banner-plan") { app in
                app.section = .schedule
                app.scheduleTab.smokeSet(auth: .signedIn(name: "Sample Student")) { $0.source = .bannerPlan; $0.selectedIndex = 0 }
            },
            SmokeScene(name: "schedule-signed-out") { app in
                app.section = .schedule
                app.scheduleTab.smokeSet(auth: .signedOut) { $0.source = .bannerPlan }
                app.scheduleTab.smokeHidePlans(true)
            } cleanup: { app in
                app.scheduleTab.smokeHidePlans(false)
                app.scheduleTab.smokeSet { $0.source = .route }
            },
            SmokeScene(name: "schedule-sign-in-sheet", window: .sheet) { app in
                app.section = .schedule
                app.scheduleTab.showSignIn = true
            } cleanup: { app in
                app.scheduleTab.showSignIn = false
            },
            SmokeScene(name: "schedule-dark", settle: 1.5) { app in
                app.section = .schedule
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                app.scheduleTab.smokeSet(auth: .signedIn(name: "Sample Student")) { $0.source = .route; $0.selectedIndex = 1 }
            } cleanup: { app in
                app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
                app.scheduleTab.smokeSet { $0.selectedIndex = 0 }
            },
            SmokeScene(name: "schedule-block-times-dark", settle: 1.5) { app in
                app.section = .schedule
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                app.scheduleTab.smokeSet(blockMode: true) { s in
                    s.blocks = [TimetableBlock(id: "d1", day: .tuesday, start: 12 * 60, end: 14 * 60, label: "Work")]
                }
            } cleanup: { app in
                app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
                app.scheduleTab.smokeSet(blockMode: false) { $0.blocks = [] }
            },
        ]
    }
}
