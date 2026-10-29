import DraftKit
import SwiftUI
import WebKit

/// Live HTML preview of the document. The page loads once; later edits replace `#content` in place,
/// so the scroll position survives. Page JavaScript is off; only the app's own scripts run.
struct PreviewView: NSViewRepresentable {
    let markdown: String
    let documentFolder: URL?
    let topLine: Int
    var font: EditorFont = .duo

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        coordinator.assets.documentFolder = documentFolder
        coordinator.font = font
        coordinator.show(markdown: markdown)
        coordinator.lastMarkdown = markdown
        return coordinator.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.assets.documentFolder = documentFolder
        if coordinator.font != font { coordinator.font = font }
        if coordinator.lastMarkdown != markdown {
            coordinator.lastMarkdown = markdown
            coordinator.scheduleUpdate(markdown: markdown)
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
        private var pageRequested = false
        private var crashedMarkdown: String?
        private var crashes = 0
        private var pendingBody: String?
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var updateTask: Task<Void, Never>?
        private var lastLine = 0
        private var requestedLine = 0
        /// Body font; changing it restyles the loaded page in place.
        var font: EditorFont = .duo {
            didSet { if loaded { applyFont() } }
        }

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
            if !pageRequested {
                pageRequested = true
                loaded = false
                pageLoads += 1
                let page = PreviewRenderer.page(for: markdown, title: "Preview", css: PreviewAssets.previewCSS(font: font),
                                                folder: documentFolder)
                webView.loadHTMLString(page, baseURL: PreviewAssets.baseURL)
                return
            }
            let body = PreviewRenderer.body(for: markdown, folder: documentFolder)
            if loaded { replaceContent(body) } else { pendingBody = body }
        }

        /// Debounced `show`: renders 300 ms after the last call; each call replaces the pending one.
        func scheduleUpdate(markdown: String) {
            updateTask?.cancel()
            updateTask = Task { [weak self] in
                try? await Task.sleep(for: Self.updateDelay)
                guard !Task.isCancelled else { return }
                self?.show(markdown: markdown)
            }
        }

        /// Where `/path` content blocks are read from: the same folder the asset handler serves.
        private var documentFolder: DocumentFolder? { assets.documentFolder.map(DocumentFolder.init(url:)) }

        private func applyFont() {
            webView.evaluateJavaScript(
                "document.documentElement.style.setProperty('--body-font', '\"\(font.cssFamily)\"')")
        }

        /// Scrolls to the source line at the editor's top. Remembered while a page loads and applied on load.
        func scroll(toLine line: Int) {
            requestedLine = line
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

        /// Web and mail links go to the default app; in-document anchors and relative links stay put.
        static func opensExternally(_ url: URL) -> Bool {
            ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
        }

        static func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
            action.navigationType == .linkActivated ? .cancel : .allow
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            let policy = Self.policy(for: action)
            if policy == .cancel, let url = action.request.url, Self.opensExternally(url) { NSWorkspace.shared.open(url) }
            return policy
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let body = pendingBody {
                pendingBody = nil
                replaceContent(body)
            }
            // Settings that changed while the page was loading (or before a crash reload).
            applyFont()
            lastLine = 0
            if requestedLine > 1 { scroll(toLine: requestedLine) }
            releaseWaiters()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            releaseWaiters()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            releaseWaiters()
        }

        /// The page's process crashed (or was killed for memory): load the page again with the latest text.
        /// A text that crashes it every time gets two retries, then a notice until the next edit.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            releaseWaiters()
            loaded = false
            pageRequested = false
            lastLine = 0
            if crashedMarkdown == lastMarkdown { crashes += 1 } else { crashedMarkdown = lastMarkdown; crashes = 1 }
            if crashes <= Self.crashRetries {
                show(markdown: lastMarkdown)
            } else {
                webView.loadHTMLString(Self.crashNotice, baseURL: nil)
            }
        }

        static let crashRetries = 2
        static let crashNotice = """
        <html><body style="font: 13px -apple-system; color: gray; text-align: center; padding-top: 40vh">
        The preview crashed while rendering this document. It will try again after your next edit.
        </body></html>
        """

        private func releaseWaiters() {
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }
}
