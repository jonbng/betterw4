//
//  W4WebView.swift
//  BetterW4
//
//  A generic authenticated WKWebView for W4's CMS-shaped pages.
//

import SwiftUI
import UIKit
import WebKit

/// Renders an authenticated `w4.uwcrcn.no` page inside the app.
///
/// Login is native (`W4LoginClient`); this view knows nothing about it. It exists for the
/// pages that are cheaper to *render* than to reparse — Documents and subject pages
/// (`documents/index`, `academics/subjects/pages`), transcripts, and the generated Letter of
/// Attendance, which is ~600 KB of HTML. It injects `PHPSESSID` into its own cookie store
/// before the first load, keeps W4 navigation in-app, and hands anything else to Safari.
///
/// Session death still follows README §4.5: landing on `r=site/login` means the cookie is
/// dead, so the view stops and posts `.w4SessionExpired` like every other W4 call path.
struct W4WebView: UIViewRepresentable {
    /// The page to show. Build it with `W4Routes.url(_:_:)`.
    let url: URL
    /// The session to render the page with. Changing it reloads.
    var credentials: W4Credentials
    var onLoadingChanged: ((Bool) -> Void)? = nil
    /// Fired for every main-frame page the WebView commits to, so a host view can keep a
    /// title or a "open in Safari" action in sync.
    var onNavigated: ((URL) -> Void)? = nil
    var onError: ((Error) -> Void)? = nil

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Same stable desktop UA as the native client: W4 is a 2016-era jQuery app with no
        // mobile layout, and one consistent UA keeps the server-side device story boring.
        webView.customUserAgent = W4UserAgent.value

        // Registered so `CookieManager.syncCredentialsToWebViews` reaches this store too.
        W4ActiveWebViewRegistry.shared.add(webView)

        context.coordinator.load(url: url, credentials: credentials, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.needsReload(url: url, credentials: credentials) else { return }
        context.coordinator.load(url: url, credentials: credentials, into: webView)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        W4ActiveWebViewRegistry.shared.remove(uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: W4WebView

        private var loadedURL: URL?
        private var loadedSessionId: String?

        init(parent: W4WebView) {
            self.parent = parent
        }

        /// True when the page or the session changed since the last load we started.
        func needsReload(url: URL, credentials: W4Credentials) -> Bool {
            loadedURL != url || loadedSessionId != credentials.sessionId
        }

        /// Puts `PHPSESSID` in this WebView's own cookie store *before* loading, so the very
        /// first request is authenticated and W4 never gets a chance to 302 us to the login
        /// page.
        func load(url: URL, credentials: W4Credentials, into webView: WKWebView) {
            loadedURL = url
            loadedSessionId = credentials.sessionId

            guard let cookie = Self.sessionCookie(for: credentials) else {
                start(url: url, in: webView)
                return
            }
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.start(url: url, in: webView)
            }
        }

        private func start(url: URL, in webView: WKWebView) {
            parent.onLoadingChanged?(true)
            webView.load(URLRequest(url: url))
        }

        /// Host-only, path `/`, `Secure`, no expiry — exactly how W4 sets it (README §4.1).
        private static func sessionCookie(for credentials: W4Credentials) -> HTTPCookie? {
            guard !credentials.sessionId.isEmpty else { return nil }
            return HTTPCookie(properties: [
                .name: CookieManager.sessionCookieName,
                .value: credentials.sessionId,
                .domain: W4Routes.host,
                .path: "/",
                .secure: true
            ])
        }

        // MARK: - WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false

            // README §4.5 signal 1: a dead cookie always ends up at `r=site/login`. Do not
            // render W4's own login form inside the app — hand it to the native flow.
            if isMainFrame, W4Routes.isLoginURL(target) {
                decisionHandler(.cancel)
                parent.onLoadingChanged?(false)
                parent.onError?(W4Error.sessionExpired)
                NotificationCenter.default.post(name: .w4SessionExpired, object: nil)
                return
            }

            if W4Routes.isW4Host(target.host) || !isMainFrame {
                decisionHandler(.allow)
                return
            }

            // W4's Links block points at ManageBac, Google Sites and Drive. Tapping one of
            // those should leave the app, not turn this into a general-purpose browser.
            if navigationAction.navigationType == .linkActivated,
               let scheme = target.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                decisionHandler(.cancel)
                parent.onLoadingChanged?(false)
                UIApplication.shared.open(target)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard let current = webView.url else { return }
            parent.onNavigated?(current)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadingChanged?(false)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        private func report(_ error: Error) {
            parent.onLoadingChanged?(false)
            // A cancelled load is what every "user tapped another link mid-load" looks like.
            if (error as? URLError)?.code == .cancelled { return }
            print("❌ [W4WebView] \(error.localizedDescription)")
            parent.onError?(error)
        }
    }
}
