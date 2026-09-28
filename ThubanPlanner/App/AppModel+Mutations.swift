import Foundation
import ThubanPlannerCore

/// Every write the UI can make. Each is one `mutate` (normalize → recompute route → atomic save). Atlas's rules
/// live in the core (`PlannerData+Mutations`).
extension AppModel {
    // MARK: Semesters

    /// "+ Semester": adds a past / current term (an existing key is left as it is and returned).
    @discardableResult
    func addTerm(season: Season, year: Int, current: Bool = false) -> Term? {
        mutate { $0.addTerm(season: season, year: year, current: current) }
    }

    /// Makes `key` the current semester (the chip's "Mark as current").
    func setCurrentTerm(_ key: String) { mutate { $0.setCurrentTerm(key) } }

    /// Removes a semester; its classes go back to "To take".
    func removeTerm(_ key: String) { mutate { $0.removeTerm(key) } }

    /// Switches a (summer) term off / on for the planner.
    func toggleDisabledTerm(_ key: String) { mutate { $0.toggleDisabledTerm(key) } }

    // MARK: Classes

    /// "Add class": a new class (Atlas adds `title: "New class", credits: 3`). Selects it and asks its row to
    /// start editing. Returns nil when both code and title are empty.
    @discardableResult
    func addCourse(code: String = "", title: String = "New class", credits: Double = 3, prereqs: [String] = [], coreqs: [String] = [],
                   summerOk: Bool = false, term: String? = nil) -> Course? {
        let course = mutate { $0.addCourse(code: code, title: title, credits: credits, prereqs: prereqs, coreqs: coreqs,
                                           summerOk: summerOk, term: term) }
        if let course {
            selectedCourseId = course.id
            editRequestCourseId = course.id
        }
        return course
    }

    /// Patches one class (code / title / credits / prereqs / coreqs / summerOk / term). Text is trimmed, refs are
    /// cleaned, invalid credits are ignored. Commit text on submit / focus loss, not per keystroke.
    @discardableResult
    func updateCourse(_ id: String, _ patch: CoursePatch) -> Course? { mutate { $0.updateCourse(id, patch) } }

    /// Sets which term a class was taken in (nil = "To take").
    func setTerm(of courseId: String, to termKey: String?) { updateCourse(courseId, CoursePatch(term: .some(termKey))) }

    /// Requirement fields from their comma-separated text ("MATH 1241, PHYS 2101").
    func setPrereqs(of courseId: String, text: String) { updateCourse(courseId, CoursePatch(prereqs: CoursePatch.refs(fromText: text))) }
    func setCoreqs(of courseId: String, text: String) { updateCourse(courseId, CoursePatch(coreqs: CoursePatch.refs(fromText: text))) }

    func removeCourse(_ id: String) { mutate { $0.removeCourse(id) } }

    // MARK: Planning settings

    /// Most credits in a fall / spring term (0 or less resets to 15 on the next load, like Atlas).
    func setMaxCredits(_ value: Double) { mutate { $0.setSetting(.maxCredits(value)) } }
    func setSummerMax(_ value: Double) { mutate { $0.setSetting(.summerMax(value)) } }
    func setStrategy(_ strategy: Strategy) { mutate { $0.setSetting(.strategy(strategy)) } }
}
