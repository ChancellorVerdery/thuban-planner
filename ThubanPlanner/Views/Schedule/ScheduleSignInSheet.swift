import SwiftUI
import ThubanPlannerCore
import WebKit

/// "Sign in to Banner": UNC Charlotte's own sign-in page in an embedded web view on the app's persistent WebKit store.
/// The user types their credentials into UNC Charlotte's page; the app never sees or stores them (no Keychain). When
/// a signed-in Banner page loads, the footer says so and Done continues (the plan is read after the sheet closes).
/// Every navigation passes `BannerNavigationGuard`, and the read-only content rules block writes to Banner.
struct ScheduleSignInSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: WKWebViewConfiguration?
    @State private var currentHost = ""
    @State private var isLoading = false
    @State private var blockedMessage: String?

    var body: some View {
        let model = app.scheduleTab
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow("UNC Charlotte sign-in")
                    Text("Sign in to Banner")
                        .font(ThubanFont.display(24))
                        .foregroundStyle(theme.inkColor)
                    Text("You’re signing in on UNC Charlotte’s own page. Thuban Planner never sees or stores your password — it only reads your Plan Ahead classes, and never registers or changes anything.")
                        .font(ThubanFont.body(13))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                IconButton(.close, label: "Close", size: 30, iconSize: 14) { dismiss() }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.posTextColor)
                Text(currentHost.isEmpty ? "selfservice.uncc.edu" : currentHost)
                    .font(ThubanFont.mono(12))
                    .foregroundStyle(theme.inkDimColor)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(theme.panel2Color)

            ZStack {
                theme.bgColor
                if let configuration, !model.offline {
                    ScheduleWebView(configuration: configuration, start: BannerWebKit.planTermSelectionURL,
                                    onPage: pageLoaded, onLoading: { isLoading = $0 }, onBlocked: { blockedMessage = $0 })
                } else if model.offline {
                    VStack(spacing: 8) {
                        Icon(.schedule, size: 26).foregroundStyle(theme.inkFaintColor)
                        Text("UNC Charlotte’s sign-in page appears here.")
                            .font(ThubanFont.body(13))
                            .foregroundStyle(theme.inkFaintColor)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(Rectangle().strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))

            HStack(spacing: 10) {
                Circle().fill(model.auth.isSignedIn ? theme.posColor : theme.inkFaintColor).frame(width: 8, height: 8)
                Text(footerText(model))
                    .font(ThubanFont.body(13))
                    .foregroundStyle(blockedMessage != nil ? theme.negTextColor : theme.inkDimColor)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.thubanSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(model.auth.isSignedIn ? "Read my plan" : "Done") { dismiss() }
                    .buttonStyle(.thubanPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .frame(height: 64)
            .background(theme.panelColor)
            .thubanHairline(.top, color: theme.lineColor)
        }
        .frame(width: 900, height: 700)
        .background(theme.panelColor)
        .task {
            if configuration == nil, !model.offline { configuration = await BannerWebKit.configuration() }
        }
    }

    private func footerText(_ model: ScheduleModel) -> String {
        if let blockedMessage { return blockedMessage }
        switch model.auth {
        case .signedIn(let name): return "Signed in\(name.map { " as \($0)" } ?? ""). You can close this and read your plan."
        default: return "Sign in with your NinerNET account. Duo may ask you to approve the sign-in."
        }
    }

    private func pageLoaded(_ url: URL, fullName: String?) {
        currentHost = url.host ?? ""
        let onBanner = url.host?.lowercased() == BannerRequestGuard.host && !BannerPage.isSignInURL(url)
        if onBanner, (fullName?.isEmpty == false) || url.path.lowercased().contains("termselection") || url.path.lowercased().contains("/plan/") {
            app.scheduleTab.didSignIn(name: fullName.flatMap { $0.isEmpty ? nil : $0 })
        }
    }
}

/// The sign-in web view. Navigation policy = `BannerNavigationGuard`; reports every finished page (with the
/// `fullName` meta Banner puts on signed-in pages).
private struct ScheduleWebView: NSViewRepresentable {
    var configuration: WKWebViewConfiguration
    var start: URL
    var onPage: (URL, String?) -> Void
    var onLoading: (Bool) -> Void
    var onBlocked: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        context.coordinator.policy.onBlocked = { why in context.coordinator.parent.onBlocked(why) }
        view.load(URLRequest(url: start))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { context.coordinator.parent = self }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ScheduleWebView
        let policy = BannerNavigationGuard()

        init(_ parent: ScheduleWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            decisionHandler(policy.decide(navigationAction))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { parent.onLoading(true) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoading(false)
            guard let url = webView.url else { return }
            webView.evaluateJavaScript("document.querySelector('meta[name=\"fullName\"]')?.content || ''") { [weak self] value, _ in
                MainActor.assumeIsolated { self?.parent.onPage(url, value as? String) }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.onLoading(false) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.onLoading(false) }
    }
}
