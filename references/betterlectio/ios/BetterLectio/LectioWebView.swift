//
//  LectioWebView.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import SwiftUI
import WebKit

/// SwiftUI wrapper for WKWebView used for MitID authentication
struct LectioWebView: UIViewRepresentable {
    let url: URL
    let isCallbackURL: (URL) -> Bool
    let onAuthComplete: (Result<WKWebView, Error>) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        LectioActiveWebViewRegistry.shared.add(webView)
        webView.navigationDelegate = context.coordinator

        // Load the initial URL
        let request = URLRequest(url: url)
        webView.load(request)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No updates needed
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        LectioActiveWebViewRegistry.shared.remove(uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LectioWebView
        private var hasCompletedAuth = false
        private let startTime = TimeProvider.now
        private var detectedCallbackURL: URL?

        init(parent: LectioWebView) {
            self.parent = parent
        }

        // MARK: - Navigation Delegate Methods

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let elapsed = TimeProvider.now.timeIntervalSince(startTime)
            print("📍 [\(String(format: "%.1f", elapsed))s] Navigation to: \(LectioRequestLog.compactPath(for: url))")

            // Check if this is the callback URL
            if parent.isCallbackURL(url) {
                print("✅ Detected callback URL!")

                // Special case: If already at forside.aspx, extract cookies immediately
                if url.absoluteString.contains("/forside.aspx") {
                    print("✅ Already logged in (forside.aspx detected)")
                    // Cancel navigation and extract cookies now
                    decisionHandler(.cancel)
                    completeAuthentication(webView: webView)
                    return
                }

                // Otherwise, allow navigation and wait for page to load
                detectedCallbackURL = url
                decisionHandler(.allow)
                return
            }

            // Allow all other navigation
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let elapsed = TimeProvider.now.timeIntervalSince(startTime)
            guard let url = webView.url else { return }

            print("📍 [\(String(format: "%.1f", elapsed))s] Page loaded: \(LectioRequestLog.compactPath(for: url))")

            // If we detected a callback URL and the page has loaded, complete authentication
            if detectedCallbackURL != nil {
                print("⏳ Waiting 0.3s for cookies to be set...")
                // Small delay to ensure cookies are fully set
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.completeAuthentication(webView: webView)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            print("❌ Navigation failed: \(error.localizedDescription)")
            if !hasCompletedAuth {
                hasCompletedAuth = true
                parent.onAuthComplete(.failure(LectioError.networkError(error)))
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            print("❌ Provisional navigation failed: \(error.localizedDescription)")
            // Don't fail on provisional errors - sometimes MitID app switching causes this
            // Only fail if we haven't completed auth yet
        }

        // MARK: - Authentication Completion

        private func completeAuthentication(webView: WKWebView) {
            guard !hasCompletedAuth else { return }
            hasCompletedAuth = true

            let elapsed = TimeProvider.now.timeIntervalSince(startTime)
            print("✅ [\(String(format: "%.1f", elapsed))s] Authentication complete!")

            parent.onAuthComplete(.success(webView))
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var showWebView = true

        var body: some View {
            if showWebView {
                NavigationView {
                    LectioWebView(
                        url: URL(string: "https://www.lectio.dk/lectio/504/login.aspx")!,
                        isCallbackURL: { url in
                            let urlString = url.absoluteString
                            return urlString.contains("lectio.dk/lectio/integration/unilogin.aspx")
                                && !urlString.contains("broker.unilogin.dk")
                        },
                        onAuthComplete: { result in
                            switch result {
                            case .success:
                                print("Preview: Auth success")
                            case .failure(let error):
                                print("Preview: Auth failed: \(error)")
                            }
                        }
                    )
                    .navigationTitle("Log ind med MitID")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Annuller") {
                                showWebView = false
                            }
                        }
                    }
                }
            } else {
                Text("Webbrowser lukket")
            }
        }
    }

    return PreviewWrapper()
}
