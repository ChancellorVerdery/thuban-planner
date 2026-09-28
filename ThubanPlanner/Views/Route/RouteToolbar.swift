import SwiftUI
import ThubanPlannerCore

/// The Route's section-bar toolbar. OWNER: Engineer B. PLACEHOLDER — spec: legend chips · zoom − / + · `Fit`.
struct RouteToolbar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ToolbarButton("Fit", icon: .fit) { app.routeFitRequest += 1 }
    }
}
