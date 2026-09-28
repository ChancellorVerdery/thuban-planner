import Foundation
import Observation
import ThubanPlannerCore

/// Planner UI state shared between the section view and its toolbar and kept across section switches (the filter,
/// search, the Add-semester form, pending confirmations). Planner-local; not persisted. Smoke scenes set it to stage
/// states.
@MainActor
@Observable
final class PlannerViewState {
    static let shared = PlannerViewState()

    var filter: PlannerClassFilter = .all
    var search = ""
    /// The inline Add-semester form inside the Semesters card.
    var isAddingSemesterInline = false
    /// The toolbar's "+ Semester" popover.
    var isAddingSemesterPopover = false
    /// A class waiting for the remove confirmation.
    var pendingRemovalCourseId: String?
    /// A semester waiting for the remove confirmation.
    var pendingRemovalTermKey: String?
    /// SMOKE / programmatic: ask the table to focus a cell (consumed by the view).
    var focusRequest: PlannerFocus?

    func reset() {
        filter = .all
        search = ""
        isAddingSemesterInline = false
        isAddingSemesterPopover = false
        pendingRemovalCourseId = nil
        pendingRemovalTermKey = nil
        focusRequest = nil
    }
}

/// The editable columns of the class table, in Tab order.
enum PlannerColumn: String, Hashable, CaseIterable {
    case code, title, credits, prereqs, coreqs
}

/// Keyboard focus inside the Planner: the table itself (↑ ↓ Return ⌫) or one editable cell.
enum PlannerFocus: Hashable {
    case table
    case cell(String, PlannerColumn)

    var courseId: String? {
        if case .cell(let id, _) = self { return id }
        return nil
    }
}
