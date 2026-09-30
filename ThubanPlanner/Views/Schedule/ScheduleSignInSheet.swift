import SwiftUI
import ThubanPlannerCore
import WebKit

/// "Sign in to UNC Charlotte": UNC Charlotte's own sign-in page in an embedded web view on the app's persistent WebKit
/// store. Opens only when the user chooses to sign in (sidebar) or starts an export. The user types their credentials
/// into UNC Charlotte's page; the app never sees or stores them (no Keychain) and never signs in by itself. The sheet
/// opens UNC Charlotte's sign-in page for Banner (`BannerPlanExport.signInURL`). "Signed in" is decided by asking Banner
/// (a student-only JSON endpoint answers with data only for a signed-in session — `BannerWebKit.sessionState`), never
/// by which pages were visited; then the footer says so and the button continues (to the export, if one is waiting).
/// Every navigation passes `BannerNavigationGuard`, and content rules block every write to Banner in this view.
struct ScheduleSignInSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: WKWebViewConfiguration?
    @State private var currentHost = ""
    @State private var isLoading = false
    @State private var blockedMessage: String?
    /// On a Banner page, but Banner says the session isn't signed in (e.g. the public landing page).
    @State private var onBannerSignedOut = false
    /// Bumped to send the web view back to the sign-in page.
    @State private var restartToken = 0

    var body: some View {
        let model = app.scheduleTab
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow("UNC Charlotte account")
                    Text("Sign in to UNC Charlotte")
                        .font(ThubanFont.display(24))
                        .foregroundStyle(theme.inkColor)
                    Text(model.exportAfterSignIn
     ? "Sign in on UNC Charlotte’s own page to export this schedule as a Plan Ahead plan. Thuban Planner never sees or stores your password, and never registers you."
     : "You’re signing in on UNC Charlotte’s own page. Thuban Planner never sees or stores your password. Signing in is only needed to export a schedule as a Plan Ahead plan — it never registers you.")
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
                    ScheduleWebView(configuration: configuration, start: BannerWebKit.signInURL, restartToken: restartToken,
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
                if onBannerSignedOut, !model.auth.isSignedIn {
                    Button("Go to sign-in page") {
                        onBannerSignedOut = false
                        restartToken += 1
                    }
                    .buttonStyle(.thubanSecondary)
                }
                Button("Cancel") { dismiss() }
                    .buttonStyle(.thubanSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(model.auth.isSignedIn ? (model.exportAfterSignIn ? "Continue to export" : "Done") : "Done") { dismiss() }
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
            if configuration == nil, !model.offline { configuration = await BannerWebKit.signInConfiguration() }
        }
        .onDisappear { model.signInSheetClosed() }
    }

    private func footerText(_ model: ScheduleModel) -> String {
        if let blockedMessage { return blockedMessage }
        switch model.auth {
        case .signedIn(let name): return "Signed in\(name.map { " as \($0)" } ?? "")." + (model.exportAfterSignIn ? " Continue to review the plan before anything is created." : " You can close this.")
        default:
            if onBannerSignedOut { return "This Banner page isn’t signed in yet. Use “Go to sign-in page” and sign in with your NinerNET account." }
        }
        switch model.auth {
        case .expired: return "Your earlier sign-in ended. Sign in with your NinerNET account; Duo may ask you to approve it."
        default: return "Sign in with your NinerNET account. Duo may ask you to approve the sign-in."
        }
    }

    private func pageLoaded(_ url: URL, fullName: String?, webView: WKWebView) {
        currentHost = url.host ?? ""
        guard url.host?.lowercased() == BannerRequestGuard.host, !url.path.lowercased().contains("/login") else {
            onBannerSignedOut = false
            return
        }
        // On a Banner page: ask Banner whether this session is signed in.
        Task { @MainActor in
            switch await BannerWebKit.sessionState(in: webView) {
            case .signedIn:
                onBannerSignedOut = false
                app.scheduleTab.didSignIn(name: fullName.flatMap { $0.isEmpty ? nil : $0 })
            case .signedOut:
                onBannerSignedOut = true
                app.scheduleTab.markNotSignedIn()
            case .unknown:
                break
            }
        }
    }
}

/// The sign-in web view. Navigation policy = `BannerNavigationGuard`; reports every finished page (with the
/// `fullName` meta Banner puts on signed-in pages).
private struct ScheduleWebView: NSViewRepresentable {
    var configuration: WKWebViewConfiguration
    var start: URL
    var restartToken: Int
    var onPage: (URL, String?, WKWebView) -> Void
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

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.restartToken != restartToken {
            context.coordinator.restartToken = restartToken
            nsView.load(URLRequest(url: start))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ScheduleWebView
        let policy = BannerNavigationGuard()
        var restartToken = 0

        init(_ parent: ScheduleWebView) {
            self.parent = parent
            restartToken = parent.restartToken
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            decisionHandler(policy.decide(navigationAction))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { parent.onLoading(true) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoading(false)
            guard let url = webView.url else { return }
            webView.evaluateJavaScript("document.querySelector('meta[name=\"fullName\"]')?.content || ''") { [weak self] value, _ in
                MainActor.assumeIsolated { self?.parent.onPage(url, value as? String, webView) }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.onLoading(false) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.onLoading(false) }
    }
}
