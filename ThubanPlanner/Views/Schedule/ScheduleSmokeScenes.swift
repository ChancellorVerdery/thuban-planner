import Foundation
import ThubanPlannerCore

/// Schedule smoke scenes (offline: sample terms and sections seeded by `ScheduleModel.seedOfflineSample`).
extension SmokeScenes {
    static var schedule: [SmokeScene] {
        [
            SmokeScene(name: "schedule-route") { app in
                app.section = .schedule
                app.scheduleTab.smokeSet { $0.selectedIndex = 0 }
            },
            SmokeScene(name: "schedule-expanded-course") { app in
                app.section = .schedule
                app.scheduleTab.smokeSet { $0.selectedIndex = 2 }
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
            SmokeScene(name: "schedule-dark", settle: 1.5) { app in
                app.section = .schedule
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                app.scheduleTab.smokeSet { $0.selectedIndex = 1 }
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
            SmokeScene(name: "schedule-class-detail-combined", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.ratings.smokeFill(["Dana Whitfield"])
                app.scheduleTab.smokeShowDetail(instructors: ["Dana Whitfield"], examMeeting: true)
            } cleanup: { app in
                app.scheduleTab.detail = nil
            },
            SmokeScene(name: "schedule-class-detail-single", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeShowDetail(instructors: ["Marcus Oyelaran", "Owen Lindqvist"])
            } cleanup: { app in
                app.scheduleTab.detail = nil
            },
            SmokeScene(name: "schedule-class-detail-not-found", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeShowDetail(instructors: ["Priya Raman"])
            } cleanup: { app in
                app.scheduleTab.detail = nil
            },
            SmokeScene(name: "schedule-class-detail-ambiguous", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeShowDetail(instructors: ["Chen, L."])
            } cleanup: { app in
                app.scheduleTab.detail = nil
            },
            SmokeScene(name: "schedule-class-detail-no-instructor", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeShowDetail(instructors: [])
            } cleanup: { app in
                app.scheduleTab.detail = nil
            },
            SmokeScene(name: "schedule-class-detail-offline", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.ratings.smokeReset(failing: ["Grace Okafor"])
                app.scheduleTab.smokeShowDetail(instructors: ["Grace Okafor"])
            } cleanup: { app in
                app.scheduleTab.detail = nil
                app.scheduleTab.ratings.smokeReset()
            },
            SmokeScene(name: "schedule-class-detail-dark", window: .sheet, settle: 1.6) { app in
                app.section = .schedule
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                app.scheduleTab.ratings.smokeFill(["Dana Whitfield"])
                app.scheduleTab.smokeShowDetail(instructors: ["Dana Whitfield"], examMeeting: true)
            } cleanup: { app in
                app.scheduleTab.detail = nil
                app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            },
            SmokeScene(name: "schedule-sort-highest-rating", settle: 2.2) { app in
                app.section = .schedule
                app.scheduleTab.ratings.smokeReset()
                app.scheduleTab.smokeSet { $0.sorts = [.highestRated]; $0.selectedIndex = 0 }
                app.scheduleTab.expandedCourse = app.scheduleTab.rows.first?.code
            } cleanup: { app in
                app.scheduleTab.expandedCourse = nil
            },
            SmokeScene(name: "schedule-sort-combined", settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeSet { $0.sorts = [.fewestDays, .highestRated, .leastGaps]; $0.selectedIndex = 0 }
            },
            SmokeScene(name: "schedule-sort-menu", window: .popover, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeSet { $0.sorts = [.fewestDays, .highestRated, .leastGaps]; $0.selectedIndex = 0 }
                app.scheduleTab.sortMenuOpen = true
            } cleanup: { app in
                app.scheduleTab.sortMenuOpen = false
                app.scheduleTab.smokeSet { $0.sorts = TimetableSort.defaultList; $0.selectedIndex = 0 }
                app.scheduleTab.ratings.smokeReset()
            },
            SmokeScene(name: "schedule-account-signed-out") { app in
                app.section = .schedule
                app.scheduleTab.smokeSetAuth(.signedOut)
                app.scheduleTab.smokeSet { $0.selectedIndex = 0 }
            },
            SmokeScene(name: "schedule-sign-in-sheet", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeSetAuth(.signedOut)
                app.scheduleTab.exportAfterSignIn = true
                app.scheduleTab.showSignIn = true
            } cleanup: { app in
                app.scheduleTab.exportAfterSignIn = false
                app.scheduleTab.showSignIn = false
            },
            SmokeScene(name: "schedule-export-confirm", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeSet { $0.selectedIndex = 2 }
                app.scheduleTab.smokeShowExport(.ready)
            } cleanup: { app in
                app.scheduleTab.exportDraft = nil
            },
            SmokeScene(name: "schedule-export-working", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeShowExport(.ready)
                let second = app.scheduleTab.exportDraft?.items.dropFirst().first
                app.scheduleTab.updateDraft { $0.phase = .working("Adding \(second?.courseCode ?? "a class") (2 of \($0.items.count))…") }
            } cleanup: { app in
                app.scheduleTab.exportDraft = nil
            },
            SmokeScene(name: "schedule-export-success", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeShowExport(.ready)
                if let d = app.scheduleTab.exportDraft {
                    app.scheduleTab.updateDraft { $0.phase = .done(BannerExportOutcome(planName: d.name, sequenceNumber: 3, classCount: d.items.count,
                                                                                         verified: true, note: nil, dryRun: false)) }
                }
            } cleanup: { app in
                app.scheduleTab.exportDraft = nil
            },
            SmokeScene(name: "schedule-export-failure", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeShowExport(.ready)
                if let first = app.scheduleTab.exportDraft?.items.first {
                    app.scheduleTab.updateDraft { $0.phase = .failed("Banner didn’t accept \(first.courseCode) \(first.section). CRN \(first.crn): This section is not available for planning. No plan was saved.",
                                                                     wroteNothing: true) }
                }
            } cleanup: { app in
                app.scheduleTab.exportDraft = nil
            },
            SmokeScene(name: "schedule-export-max-plans", window: .sheet, settle: 1.4) { app in
                app.section = .schedule
                app.scheduleTab.smokeShowExport(.full(count: 5, max: 5),
                                                preflight: BannerExportPreflight(studentName: "Sample Student", planCount: 5, maxPlans: 5))
            } cleanup: { app in
                app.scheduleTab.exportDraft = nil
            },
            SmokeScene(name: "schedule-export-confirm-dark", window: .sheet, settle: 1.6) { app in
                app.section = .schedule
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                app.scheduleTab.smokeShowExport(.ready)
            } cleanup: { app in
                app.scheduleTab.exportDraft = nil
                app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            },
            SmokeScene(name: "schedule-account-signed-in-dark", settle: 1.5) { app in
                app.section = .schedule
                app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
                app.scheduleTab.smokeSetAuth(.signedIn(name: "Sample Student"))
            } cleanup: { app in
                app.scheduleTab.smokeSetAuth(.signedOut)
                app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            },
        ]
    }
}
