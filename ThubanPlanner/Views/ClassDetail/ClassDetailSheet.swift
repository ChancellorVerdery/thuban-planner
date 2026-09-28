import SwiftUI
import ThubanPlannerCore

/// The class detail sheet, presented by the shell when `app.presentedCourseId` is set (Route box click, Planner
/// row). OWNER: Engineer B. PLACEHOLDER — keep the type name and `init(courseId:)`. Spec: ARCHITECTURE.md ▸
/// "Class detail sheet".
struct ClassDetailSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var courseId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let course = app.course(courseId) {
                PageHeader(eyebrow: "\(app.creditsText(course.credits)) credits", title: course.displayCode, subtitle: course.title)
                ForEach(app.requirements(of: course)) { req in
                    Text("\(req.kind == .prereq ? "Prerequisite" : "Corequisite"): \(req.ref)\(req.course.map { " — \($0.title)" } ?? "")")
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkDimColor)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.thubanPrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 420, alignment: .topLeading)
        .background(theme.bgColor)
    }
}
