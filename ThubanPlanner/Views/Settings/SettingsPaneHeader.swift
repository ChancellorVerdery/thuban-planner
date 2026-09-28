import SwiftUI

/// A pane's heading: eyebrow, 32 pt serif title, dim caption (design: "FIRST RUN · ONE-TIME IMPORT" /
/// "Bring your training over from Atlas").
struct SettingsPaneHeader: View {
    var eyebrow: String?
    var title: String
    var caption: String?

    var body: some View {
        PageHeader(eyebrow: eyebrow, title: title, subtitle: caption)
    }
}
