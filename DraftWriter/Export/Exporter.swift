import AppKit
import DraftKit
import WebKit

enum PageSize: String, CaseIterable, Identifiable {
    case a4, letter

    var id: Self { self }
    var title: String { self == .a4 ? "A4" : "US Letter" }
    var size: NSSize { self == .a4 ? NSSize(width: 595.28, height: 841.89) : NSSize(width: 612, height: 792) }
}

struct ExportSource {
    let markdown: String
    let title: String
    let documentFolder: URL?
}

enum ExportError: LocalizedError {
    case pageLoadFailed, printFailed

    var errorDescription: String? {
        switch self {
        case .pageLoadFailed: "The document could not be rendered for export."
        case .printFailed: "The document could not be printed."
        }
    }
}

/// HTML, PDF and print output. All three render the same page as the preview, with the export
/// stylesheet (fonts inlined, always light). The source document is never modified.
@MainActor
enum Exporter {
    static let margin: CGFloat = 56.7   // 2 cm

    static func html(_ source: ExportSource) -> String {
        PreviewRenderer.page(for: source.markdown, title: source.title, css: PreviewAssets.exportCSS())
    }

    static func writePDF(_ source: ExportSource, to url: URL, pageSize: PageSize) async throws {
        let info = printInfo(pageSize)
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        try await runPrint(source, info: info, interactive: false)
    }

    static func print(_ source: ExportSource, pageSize: PageSize) async throws {
        try await runPrint(source, info: printInfo(pageSize), interactive: true)
    }

    private static func printInfo(_ pageSize: PageSize) -> NSPrintInfo {
        let info = NSPrintInfo()
        info.paperSize = pageSize.size
        info.orientation = .portrait
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    /// WKWebView prints asynchronously, so the operation must run modally for a window
    /// (`run()` yields blank pages). An offscreen window hosts the web view.
    private static func runPrint(_ source: ExportSource, info: NSPrintInfo, interactive: Bool) async throws {
        let page = PrintPage(source: source)
        let webView = try await page.load()
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = interactive
        operation.showsProgressPanel = interactive
        operation.view?.frame = webView.bounds
        let succeeded = await PrintRunner().run(operation, for: page.window)
        if !succeeded && !interactive { throw ExportError.printFailed }
    }
}

/// Loads the export page into an offscreen web view and waits for it to finish.
@MainActor
private final class PrintPage: NSObject, WKNavigationDelegate {
    let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 800, height: 1000),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    private let source: ExportSource
    private let assets = AssetSchemeHandler()
    private var continuation: CheckedContinuation<WKWebView, any Error>?
    private var webView: WKWebView?

    init(source: ExportSource) {
        self.source = source
    }

    func load() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(assets, forURLScheme: PreviewAssets.scheme)
        assets.documentFolder = source.documentFolder
        let webView = WKWebView(frame: window.contentLayoutRect, configuration: configuration)
        webView.navigationDelegate = self
        window.contentView = webView
        self.webView = webView
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(Exporter.html(source), baseURL: PreviewAssets.baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(returning: webView)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        continuation?.resume(throwing: ExportError.pageLoadFailed)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        continuation?.resume(throwing: ExportError.pageLoadFailed)
        continuation = nil
    }
}

/// Bridges NSPrintOperation's modal completion callback to async/await. AppKit may call back on a
/// background thread, so the callback is nonisolated; resuming a continuation is thread-safe.
private final class PrintRunner: NSObject, @unchecked Sendable {
    nonisolated(unsafe) private var continuation: CheckedContinuation<Bool, Never>?

    @MainActor
    func run(_ operation: NSPrintOperation, for window: NSWindow) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            operation.runModal(for: window, delegate: self,
                               didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    @objc nonisolated private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        continuation?.resume(returning: success)
        continuation = nil
    }
}
