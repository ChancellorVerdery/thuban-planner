import AppKit
import Foundation
import ThubanPlannerCore

/// Extra Planner smoke screens. OWNER: Engineer A. Register states here (the registry already includes this list);
/// always undo in `cleanup`.
extension SmokeScenes {
    static var planner: [SmokeScene] {
        [
            // A row selected deep in the table (scrolls the To take group into view).
            SmokeScene(name: "planner-selected") { app in
                app.section = .planner
                smokeState.reset()
                app.selectedCourseId = "c-sample-38"
                smokeState.focusRequest = .table
                try? await Task.sleep(nanoseconds: 300_000_000)
                smokeState.focusRequest = nil
                plannerSmokeScroll(to: 0.72)
            } cleanup: { app in
                app.selectedCourseId = nil
                plannerSmokeScroll(to: 0)
            },
            // "Add class": the new row scrolled into view with its Code field focused.
            SmokeScene(name: "planner-new-class", settle: 1.6) { app in
                app.section = .planner
                smokeState.reset()
                app.addCourse()
            } cleanup: { app in
                if let id = app.selectedCourseId, app.course(id)?.title == "New class" { app.removeCourse(id) }
                app.selectedCourseId = nil
                plannerSmokeScroll(to: 0)
            },
            // Editing a requirement field (chips turn into the comma-separated text).
            SmokeScene(name: "planner-edit-prereqs", settle: 1.4) { app in
                app.section = .planner
                smokeState.reset()
                app.selectedCourseId = "c-sample-37"
                smokeState.focusRequest = .cell("c-sample-37", .prereqs)
            } cleanup: { app in
                smokeState.focusRequest = .table
                try? await Task.sleep(nanoseconds: 200_000_000)
                app.selectedCourseId = nil
                plannerSmokeScroll(to: 0)
            },
            SmokeScene(name: "planner-filter-to-take") { app in
                app.section = .planner
                smokeState.reset()
                smokeState.filter = .toTake
            } cleanup: { _ in smokeState.reset() },
            SmokeScene(name: "planner-search") { app in
                app.section = .planner
                smokeState.reset()
                smokeState.search = "megr 31"
            } cleanup: { _ in smokeState.reset() },
            SmokeScene(name: "planner-search-no-match") { app in
                app.section = .planner
                smokeState.reset()
                smokeState.search = "BIOL"
            } cleanup: { _ in smokeState.reset() },
            SmokeScene(name: "planner-add-semester") { app in
                app.section = .planner
                smokeState.reset()
                smokeState.isAddingSemesterInline = true
            } cleanup: { _ in smokeState.reset() },
            // A prerequisite cycle: the scheduler's "Couldn't place" warning + unplaceable rows.
            SmokeScene(name: "planner-warnings") { app in
                app.section = .planner
                smokeState.reset()
                plannerSmokeAddCycle(app)
            } cleanup: { app in plannerSmokeRemoveCycle(app) },
            SmokeScene(name: "planner-warnings-dark") { app in
                app.section = .planner
                smokeState.reset()
                plannerSmokeAddCycle(app)
                plannerSmokeTheme(app, dark: true)
            } cleanup: { app in
                plannerSmokeRemoveCycle(app)
                plannerSmokeTheme(app, dark: false)
            },
            SmokeScene(name: "planner-selected-dark") { app in
                app.section = .planner
                smokeState.reset()
                plannerSmokeTheme(app, dark: true)
                app.selectedCourseId = "c-sample-31"
                plannerSmokeScroll(to: 0.6)
            } cleanup: { app in
                app.selectedCourseId = nil
                plannerSmokeScroll(to: 0)
                plannerSmokeTheme(app, dark: false)
            },
            // Semesters recorded, no classes yet.
            SmokeScene(name: "planner-no-classes") { app in
                app.section = .planner
                smokeState.reset()
                var data = SampleData.make(now: app.now, calendar: app.calendar)
                data.courses = []
                app.replaceData(data)
            } cleanup: { app in app.replaceData(SampleData.make(now: app.now, calendar: app.calendar)) },
            SmokeScene(name: "planner-first-run") { app in
                app.section = .planner
                smokeState.reset()
                app.replaceData(.empty); app.smokeSetFirstRun(true); app.preferences.importOffered = false
            } cleanup: { app in app.replaceData(SampleData.make(now: app.now, calendar: app.calendar)) },
            SmokeScene(name: "planner-first-run-dark") { app in
                app.section = .planner
                smokeState.reset()
                app.replaceData(.empty); app.smokeSetFirstRun(true); app.preferences.importOffered = false
                plannerSmokeTheme(app, dark: true)
            } cleanup: { app in
                app.replaceData(SampleData.make(now: app.now, calendar: app.calendar))
                plannerSmokeTheme(app, dark: false)
            },
            // The window at its minimum size.
            SmokeScene(name: "planner-compact") { app in
                app.section = .planner
                smokeState.reset()
                plannerSmokeWindow()?.setContentSize(NSSize(width: 1100, height: 700))
            } cleanup: { _ in
                plannerSmokeWindow()?.setContentSize(SmokeHarness.windowSize)
            },
            // Summer terms: Automatic (offline: the bundled Banner snapshot decides) and Manual (the stored toggles).
            SmokeScene(name: "planner-summers-automatic") { app in
                app.section = .planner
                smokeState.reset()
                app.setSummerMode(.automatic)
                plannerSmokeScroll(to: 0)
            },
            SmokeScene(name: "planner-summers-manual") { app in
                app.section = .planner
                smokeState.reset()
                app.setSummerMode(.manual)
            } cleanup: { app in app.setSummerMode(.automatic) },
            SmokeScene(name: "planner-summers-automatic-dark") { app in
                app.section = .planner
                smokeState.reset()
                app.setSummerMode(.automatic)
                plannerSmokeTheme(app, dark: true)
            } cleanup: { app in plannerSmokeTheme(app, dark: false) },
            // Transfer credit: the chip before the first semester and the "Transfer credit" group first in the table.
            SmokeScene(name: "planner-transfer") { app in
                app.section = .planner
                smokeState.reset()
                app.replaceData(SampleData.makeWithTransferCredit(now: app.now, calendar: app.calendar))
            } cleanup: { app in app.replaceData(SampleData.make(now: app.now, calendar: app.calendar)) },
            SmokeScene(name: "planner-transfer-rows") { app in
                app.section = .planner
                smokeState.reset()
                app.replaceData(SampleData.makeWithTransferCredit(now: app.now, calendar: app.calendar))
                app.selectedCourseId = "c-sample-t1"
                try? await Task.sleep(nanoseconds: 400_000_000)
                plannerSmokeScroll(to: 0.14)
            } cleanup: { app in
                app.selectedCourseId = nil
                plannerSmokeScroll(to: 0)
                app.replaceData(SampleData.make(now: app.now, calendar: app.calendar))
            },
            SmokeScene(name: "planner-transfer-dark") { app in
                app.section = .planner
                smokeState.reset()
                app.replaceData(SampleData.makeWithTransferCredit(now: app.now, calendar: app.calendar))
                plannerSmokeTheme(app, dark: true)
            } cleanup: { app in
                app.replaceData(SampleData.make(now: app.now, calendar: app.calendar))
                plannerSmokeTheme(app, dark: false)
            },
            // No transfer credit yet: the dashed "Add transfer credit" chip before the semesters (the default sample).
            SmokeScene(name: "planner-transfer-add") { app in
                app.section = .planner
                smokeState.reset()
                app.addTransferCourse()
            } cleanup: { app in
                app.replaceData(SampleData.make(now: app.now, calendar: app.calendar))
                app.selectedCourseId = nil
                plannerSmokeScroll(to: 0)
            },
        ] + electives
    }
}

@MainActor private func plannerSmokeTheme(_ app: AppModel, dark: Bool) {
    app.setThemeSelection(ThemeSelection(mode: dark ? .dark : .light, schemeId: SchemePresets.defaultId, custom: nil))
}

@MainActor private func plannerSmokeWindow() -> NSWindow? {
    NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.attachedSheet == nil && !($0 is NSPanel) }
}

/// Scrolls the Planner's scroll view to a fraction of its height (smoke only).
@MainActor private func plannerSmokeScroll(to fraction: CGFloat) {
    guard let root = plannerSmokeWindow()?.contentView else { return }
    func find(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, let doc = scroll.documentView, doc.frame.height > scroll.contentSize.height + 200 { return scroll }
        for sub in view.subviews { if let hit = find(sub) { return hit } }
        return nil
    }
    guard let scroll = find(root), let doc = scroll.documentView else { return }
    let maxY = max(0, doc.frame.height - scroll.contentSize.height)
    let y = doc.isFlipped ? maxY * fraction : maxY * (1 - fraction)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
    scroll.reflectScrolledClipView(scroll.contentView)
}

@MainActor private func plannerSmokeAddCycle(_ app: AppModel) {
    app.addCourse(code: "AERO 4100", title: "Propulsion", credits: 3, prereqs: ["AERO 4200"])
    app.addCourse(code: "AERO 4200", title: "Gas Dynamics", credits: 3, prereqs: ["AERO 4100"])
    app.editRequestCourseId = nil
    app.selectedCourseId = nil
}

@MainActor private func plannerSmokeRemoveCycle(_ app: AppModel) {
    for course in app.courses where course.code.hasPrefix("AERO 4") { app.removeCourse(course.id) }
}

@MainActor private var smokeState: PlannerViewState { PlannerViewState.shared }
