import Foundation
import ThubanPlannerCore
import WebKit
import os

/// Everything that needs the student's UNC Charlotte sign-in runs INSIDE WebKit, on the persistent default website
/// data store — the same store the sign-in sheet's web view uses. The app never reads Chrome's (or any other
/// browser's) cookies, never sees a password and never stores one: the user signs in to UNC Charlotte's own page in
/// the sheet, and the session cookies live in this app's WebKit store until "Sign out" removes them.
///
/// Read-only enforcement in WebKit: `BannerNavigationGuard` cancels any navigation to a denied write (and any POST
/// navigation to Banner outside the two allowlisted endpoints); a compiled `WKContentRuleList` blocks the same
/// fragments for fetch / XHR / every resource; the reader's own `fetch` calls pass `BannerRequestGuard.check` first.
@MainActor
enum BannerWebKit {
    static let logger = Logger(subsystem: "org.thuban.planner", category: "banner")
    private static var ruleList: WKContentRuleList?

    /// The start page for sign-in and for reading plans ("Plan Ahead" term selection).
    static var planTermSelectionURL: URL {
        URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/term/termSelection?mode=plan")!
    }

    /// A configuration on the persistent default store with the read-only content rules installed.
    static func configuration() async -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        if let list = await compiledRuleList() { config.userContentController.add(list) }
        return config
    }

    static func compiledRuleList() async -> WKContentRuleList? {
        if let ruleList { return ruleList }
        do {
            let list = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "org.thuban.planner.banner-readonly", encodedContentRuleList: BannerRequestGuard.contentRuleListJSON)
            ruleList = list
            return list
        } catch {
            logger.error("content rule list failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func isUNCC(_ domain: String) -> Bool {
        let d = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return d == "uncc.edu" || d.hasSuffix(".uncc.edu")
    }

    /// True when the app's WebKit store holds any UNC Charlotte cookie (the user signed in at some point).
    static func hasUNCCCookies() async -> Bool {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.contains { isUNCC($0.domain) }
    }

    /// Sign out: deletes every UNC Charlotte cookie and website data record (selfservice, webauth …) from the store.
    static func signOut() async {
        let store = WKWebsiteDataStore.default()
        for cookie in await store.httpCookieStore.allCookies() where isUNCC(cookie.domain) {
            await store.httpCookieStore.deleteCookie(cookie)
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let uncc = records.filter { isUNCC($0.displayName) }
        if !uncc.isEmpty { await store.removeData(ofTypes: types, for: uncc) }
    }
}

/// The navigation policy both web views use (see `BannerWebKit`).
@MainActor
final class BannerNavigationGuard {
    /// Last block, for the sign-in sheet to show.
    var onBlocked: ((String) -> Void)?

    func decide(_ action: WKNavigationAction) -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .allow }
        if case .deny(let why) = BannerRequestGuard.checkBrowser(url: url) {
            BannerWebKit.logger.notice("blocked navigation: \(url.absoluteString, privacy: .public)")
            onBlocked?(why)
            return .cancel
        }
        // Form posts to Banner itself: only the two read-only endpoints.
        if (action.request.httpMethod ?? "GET").uppercased() == "POST", url.host?.lowercased() == BannerRequestGuard.host,
           case .deny(let why) = BannerRequestGuard.check(method: "POST", url: url) {
            onBlocked?(why)
            return .cancel
        }
        return .allow
    }
}

/// A hidden web view that reads the student's Plan Ahead plans. Flow: open the plan term selection page (a sign-in
/// page instead = signed out), POST `term/search?mode=plan` for the term from inside the page (the page's own
/// synchronizer token, credentials included), open the plan page (`fwdURL`, else `plan/selectPlan`) and read
/// `JSON.stringify(window.bootstraps)` (falling back to the HTML). Never clicks anything, never submits a plan.
@MainActor
final class BannerPlanReader: NSObject, WKNavigationDelegate {
    struct Output {
        var plans: [BannerPlan]
        var studentName: String?
    }

    private var webView: WKWebView?
    private let guardPolicy = BannerNavigationGuard()
    private var pending: CheckedContinuation<URL, Error>?
    private var timeoutTask: Task<Void, Never>?

    private func view() async -> WKWebView {
        if let webView { return webView }
        let config = await BannerWebKit.configuration()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        view.navigationDelegate = self
        guardPolicy.onBlocked = { [weak self] why in self?.resume(.failure(BannerError.blocked(why))) }
        webView = view
        return view
    }

    /// Loads `url` and returns the final URL after redirects. Throws `.signedOut` when it lands on a sign-in page.
    func open(_ url: URL, timeout: Double = 30) async throws -> URL {
        if case .deny(let why) = BannerRequestGuard.checkBrowser(url: url) { throw BannerError.blocked(why) }
        let view = await view()
        pending?.resume(throwing: CancellationError())
        pending = nil
        var final: URL = try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            view.load(URLRequest(url: url))
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled, let self, let pending = self.pending else { return }
                self.pending = nil
                view.stopLoading()
                pending.resume(throwing: BannerError.network("Banner took too long to answer."))
            }
        }
        // Single sign-on may hop through a page that forwards itself by script: give it a moment before deciding.
        var hops = 0
        while BannerPage.isSignInURL(final), hops < 3 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard view.isLoading || view.url != final else { break }
            if view.isLoading {
                final = try await withCheckedThrowingContinuation { continuation in pending = continuation }
            } else if let url = view.url {
                final = url
            }
            hops += 1
        }
        if BannerPage.isSignInURL(final) { throw BannerError.signedOut }
        return final
    }

    func readPlans(termCode: String) async throws -> Output {
        _ = try await open(BannerWebKit.planTermSelectionURL)
        let view = await view()
        var name = try? await view.evaluateJavaScript("document.querySelector('meta[name=\"fullName\"]')?.content || ''") as? String

        // Select the term for the plan session from inside the page.
        let post = URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/term/search?mode=plan")!
        if case .deny(let why) = BannerRequestGuard.check(method: "POST", url: post) { throw BannerError.blocked(why) }
        let form = "term=\(termCode)&studyPath=&studyPathText=&startDatepicker=&endDatepicker="
        let script = """
        const token = document.querySelector('meta[name="synchronizerToken"]')?.content || '';
        const r = await fetch(url, { method: 'POST', credentials: 'include',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Synchronizer-Token': token,
                     'X-Requested-With': 'XMLHttpRequest' }, body: body });
        return JSON.stringify({ status: r.status, url: r.url, text: await r.text() });
        """
        let raw = try await view.callAsyncJavaScript(script, arguments: ["url": post.absoluteString, "body": form], contentWorld: .page) as? String
        var forward: URL?
        if let raw, let data = raw.data(using: .utf8), let value = try? JSONValue.parse(data) {
            if let finalURL = value["url"]?.stringValue.flatMap(URL.init(string:)), BannerPage.isSignInURL(finalURL) { throw BannerError.signedOut }
            if let text = value["text"]?.stringValue, BannerPage.looksLikeHTML(Data(text.utf8)), text.lowercased().contains("webauth") {
                throw BannerError.signedOut
            }
            if let text = value["text"]?.stringValue, let fwd = BannerPage.forwardURL(Data(text.utf8)) {
                forward = URL(string: fwd, relativeTo: URL(string: "https://selfservice.uncc.edu")!)?.absoluteURL
            }
        }

        var candidates: [URL] = []
        if let forward, forward.host?.lowercased() == BannerRequestGuard.host, !forward.path.lowercased().contains("classregistration") {
            candidates.append(forward)
        }
        candidates.append(URL(string: "https://selfservice.uncc.edu/StudentRegistrationSsb/ssb/plan/selectPlan")!)
        for url in candidates {
            _ = try await open(url)
            if name?.isEmpty ?? true {
                name = try? await view.evaluateJavaScript("document.querySelector('meta[name=\"fullName\"]')?.content || ''") as? String
            }
            var plans: [BannerPlan] = []
            if let json = try? await view.evaluateJavaScript("JSON.stringify(window.bootstraps || null)") as? String {
                plans = (try? BannerPlanParser.parse(bootstrapsJSON: Data(json.utf8))) ?? []
            }
            if plans.isEmpty, let html = try? await view.evaluateJavaScript("document.documentElement.outerHTML") as? String {
                plans = (try? BannerPlanParser.parse(html: html)) ?? []
            }
            if !plans.isEmpty { return Output(plans: plans, studentName: name.flatMap { $0.isEmpty ? nil : $0 }) }
        }
        return Output(plans: [], studentName: name.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Loads the plan term selection page and reports whether the session is signed in (and the student's name).
    func checkSession() async throws -> String? {
        _ = try await open(BannerWebKit.planTermSelectionURL)
        let name = try? await webView?.evaluateJavaScript("document.querySelector('meta[name=\"fullName\"]')?.content || ''") as? String
        return name.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(guardPolicy.decide(navigationAction))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(webView.url ?? BannerWebKit.planTermSelectionURL))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<URL, Error>) {
        guard pending != nil else { return }
        // A navigation cancelled by a redirect / our own policy reports NSURLErrorCancelled; wait for the real one.
        if case .failure(let error) = result, (error as NSError).code == NSURLErrorCancelled, (error as NSError).domain == NSURLErrorDomain { return }
        if case .failure(let error) = result, (error as NSError).domain == "WebKitErrorDomain", (error as NSError).code == 102 { return }
        resume(result.mapError { $0 is BannerError ? $0 : BannerError.network($0.localizedDescription) })
    }

    private func resume(_ result: Result<URL, Error>) {
        guard let pending else { return }
        self.pending = nil
        timeoutTask?.cancel()
        switch result {
        case .success(let url): pending.resume(returning: url)
        case .failure(let error): pending.resume(throwing: error)
        }
    }
}
