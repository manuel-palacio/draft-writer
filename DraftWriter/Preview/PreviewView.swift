import DraftKit
import SwiftUI
import WebKit

/// Live HTML preview of the document. The page loads once; later edits replace `#content` in place,
/// so the scroll position survives. Page JavaScript is off; only the app's own scripts run.
struct PreviewView: NSViewRepresentable {
    let markdown: String
    let documentFolder: URL?
    let topLine: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        coordinator.assets.documentFolder = documentFolder
        coordinator.show(markdown: markdown)
        coordinator.lastMarkdown = markdown
        return coordinator.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.assets.documentFolder = documentFolder
        if coordinator.lastMarkdown != markdown {
            coordinator.lastMarkdown = markdown
            let markdown = markdown
            Task { await coordinator.update(markdown: markdown) }
        }
        coordinator.scroll(toLine: topLine)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        static let updateDelay: Duration = .milliseconds(300)

        static let scrollScript = """
        window.draftScrollToLine = function (n) {
          let target = null;
          for (const el of document.querySelectorAll('#content [data-sourcepos]')) {
            if (parseInt(el.getAttribute('data-sourcepos'), 10) <= n) target = el; else break;
          }
          if (target) target.scrollIntoView({ block: 'start' }); else window.scrollTo(0, 0);
        };
        """

        let assets = AssetSchemeHandler()
        let webView: WKWebView
        private(set) var pageLoads = 0
        var lastMarkdown = ""
        private var loaded = false
        private var pendingBody: String?
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var generation = 0
        private var lastLine = 0

        override init() {
            let configuration = WKWebViewConfiguration()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.setURLSchemeHandler(assets, forURLScheme: PreviewAssets.scheme)
            configuration.userContentController.addUserScript(
                WKUserScript(source: Self.scrollScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            webView = WKWebView(frame: .zero, configuration: configuration)
            super.init()
            webView.navigationDelegate = self
            webView.setValue(false, forKey: "drawsBackground")   // the page paints its own background
        }

        /// Shows `markdown` now: the first call loads the page, later calls replace its content.
        func show(markdown: String) {
            if pageLoads == 0 {
                pageLoads = 1
                let page = PreviewRenderer.page(for: markdown, title: "Preview", css: PreviewAssets.previewCSS())
                webView.loadHTMLString(page, baseURL: PreviewAssets.baseURL)
                return
            }
            let body = PreviewRenderer.body(for: markdown)
            if loaded { replaceContent(body) } else { pendingBody = body }
        }

        /// Debounced `show`: only the last call within 300 ms renders.
        func update(markdown: String) async {
            generation += 1
            let mine = generation
            try? await Task.sleep(for: Self.updateDelay)
            guard mine == generation else { return }
            show(markdown: markdown)
        }

        func scroll(toLine line: Int) {
            guard loaded, line != lastLine else { return }
            lastLine = line
            webView.evaluateJavaScript("window.draftScrollToLine && window.draftScrollToLine(\(line))")
        }

        func waitUntilLoaded() async {
            if loaded { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        private func replaceContent(_ body: String) {
            guard let json = try? String(data: JSONEncoder().encode(body), encoding: .utf8) else { return }
            webView.evaluateJavaScript("document.getElementById('content').innerHTML = \(json)")
        }

        static func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
            action.navigationType == .linkActivated ? .cancel : .allow
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            let policy = Self.policy(for: action)
            if policy == .cancel, let url = action.request.url { NSWorkspace.shared.open(url) }
            return policy
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let body = pendingBody {
                pendingBody = nil
                replaceContent(body)
            }
            releaseWaiters()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            releaseWaiters()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            releaseWaiters()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            releaseWaiters()
        }

        private func releaseWaiters() {
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }
}
