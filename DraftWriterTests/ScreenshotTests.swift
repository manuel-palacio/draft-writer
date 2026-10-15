import AppKit
import DraftKit
import SwiftUI
import Testing
import WebKit
@testable import Draft_Writer

/// Renders README screenshots of the real window offscreen (this Mac has no display to capture).
/// Runs only when `DRAFT_SCREENSHOTS` is set (`TEST_RUNNER_DRAFT_SCREENSHOTS=1 xcodebuild test …`); PNGs land in
/// the sandbox container's `tmp/screenshots`, which `scripts/screenshots.sh` copies to `docs/screenshots`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["DRAFT_SCREENSHOTS"] != nil))
struct ScreenshotTests {
    static let sample = """
    # The Quiet Page

    Writing is thinking made visible. A *plain* page asks nothing of you, so the words get **all** of your attention.

    ## Why plain text

    - It opens anywhere, today and in thirty years.
    - It diffs, syncs and searches without ceremony.
    - Formatting stays out of the way until you need it.

    > Simplicity is the ultimate sophistication.

    Draft Writer keeps the tools quiet. Focus mode dims everything except the sentence you are writing, and the preview shows the finished page beside your draft.

    ```swift
    let words = TextStats.compute(draft).words
    ```

    Read more at [the project page](https://github.com/manuel-palacio/draft-writer).
    """

    let out: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("screenshots")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func settings(_ configure: (EditorSettings) -> Void) -> EditorSettings {
        let defaults = UserDefaults(suiteName: "screenshots-\(UUID().uuidString)")!
        let settings = EditorSettings(defaults: defaults)
        settings.font = .duo
        settings.fontSize = 17
        settings.columnWidth = 64
        settings.showLibrary = false
        configure(settings)
        return settings
    }

    func shoot(_ name: String, settings: EditorSettings, dark: Bool = false,
               size: NSSize = NSSize(width: 1100, height: 720), selection: NSRange? = nil) async throws {
        let library = LibraryStore(defaults: UserDefaults(suiteName: "screenshots-lib-\(UUID().uuidString)")!)
        var document = MarkdownDocument(text: Self.sample)
        let view = DocumentWindow(document: Binding(get: { document }, set: { document = $0 }),
                                  fileURL: URL(fileURLWithPath: "/tmp/The Quiet Page.md"),
                                  settings: settings, library: library)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "The Quiet Page.md"
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(size)
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(600))
        if let selection, let textView = textView(in: window.contentView!) {
            window.makeFirstResponder(textView)
            textView.setSelectedRange(selection)
        }
        try await Task.sleep(for: .seconds(2))   // styling debounce, stats, preview load

        window.displayIfNeeded()
        let frame = window.contentView!.superview!
        let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)!
        frame.cacheDisplay(in: frame.bounds, to: rep)
        let image = NSImage(size: frame.bounds.size)
        image.addRepresentation(rep)
        // WKWebView draws out of process, so cacheDisplay leaves it blank; paint its own snapshot on top.
        if let web = webView(in: frame) {
            let snapshot = try await web.takeSnapshot(configuration: nil)
            image.lockFocusFlipped(false)
            snapshot.draw(in: web.convert(web.bounds, to: frame))
            image.unlockFocus()
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: out.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    func textView(in view: NSView) -> NSTextView? {
        if let t = view as? NSTextView { return t }
        return view.subviews.lazy.compactMap { textView(in: $0) }.first
    }

    func webView(in view: NSView) -> WKWebView? {
        if let w = view as? WKWebView { return w }
        return view.subviews.lazy.compactMap { webView(in: $0) }.first
    }

    @Test func editor() async throws {
        try await shoot("editor", settings: settings { _ in }, size: NSSize(width: 900, height: 720))
    }

    @Test func focusMode() async throws {
        let cursor = (Self.sample as NSString).range(of: "Focus mode dims").location + 6
        try await shoot("focus", settings: settings { $0.focusMode = .sentence }, size: NSSize(width: 900, height: 720),
                        selection: NSRange(location: cursor, length: 0))
    }

    @Test func syntaxHighlight() async throws {
        try await shoot("highlight", settings: settings { $0.syntaxHighlight = true }, size: NSSize(width: 900, height: 720))
    }

    @Test func preview() async throws {
        try await shoot("preview", settings: settings { $0.showPreview = true; $0.columnWidth = 52 },
                        size: NSSize(width: 1400, height: 760))
    }

    @Test func dark() async throws {
        try await shoot("dark", settings: settings { _ in }, dark: true, size: NSSize(width: 900, height: 720))
    }
}
