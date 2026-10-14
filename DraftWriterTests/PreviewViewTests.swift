import Foundation
import Testing
import WebKit
@testable import Draft_Writer

@MainActor
@Suite struct PreviewViewTests {
    func text(_ preview: PreviewView.Coordinator, _ selector: String) async throws -> String? {
        try await preview.webView.evaluateJavaScript("document.querySelector('\(selector)')?.textContent") as? String
    }

    @Test func firstLoadShowsContent() async throws {
        let preview = PreviewView.Coordinator()
        preview.show(markdown: "# Title")
        await preview.waitUntilLoaded()
        #expect(try await text(preview, "#content h1") == "Title")
    }

    @Test func updateKeepsSamePageLoad() async throws {
        let preview = PreviewView.Coordinator()
        preview.show(markdown: "# Title")
        await preview.waitUntilLoaded()
        preview.show(markdown: "# New < 2")
        #expect(try await text(preview, "#content h1") == "New < 2")
        #expect(preview.pageLoads == 1)
    }

    @Test func debouncedUpdateCoalesces() async throws {
        let preview = PreviewView.Coordinator()
        preview.show(markdown: "# A")
        await preview.waitUntilLoaded()
        async let first: Void = preview.update(markdown: "# B")
        async let second: Void = preview.update(markdown: "# C")
        _ = await (first, second)
        #expect(try await text(preview, "#content h1") == "C")
        #expect(preview.pageLoads == 1)
    }

    @Test func scrollToLineDefined() async throws {
        let preview = PreviewView.Coordinator()
        preview.show(markdown: "# A\n\ntext")
        await preview.waitUntilLoaded()
        let type = try await preview.webView.evaluateJavaScript("typeof window.draftScrollToLine") as? String
        #expect(type == "function")
    }

    final class StubAction: WKNavigationAction {
        let type: WKNavigationType
        init(_ type: WKNavigationType) { self.type = type }
        override var navigationType: WKNavigationType { type }
        override var request: URLRequest { URLRequest(url: URL(string: "https://example.com")!) }
    }

    @Test func linkClicksOpenExternally() {
        #expect(PreviewView.Coordinator.policy(for: StubAction(.linkActivated)) == .cancel)
        #expect(PreviewView.Coordinator.policy(for: StubAction(.other)) == .allow)
    }
}

@MainActor
@Suite struct EditorTopLineTests {
    @Test func reportsTopVisibleLineOnScroll() {
        let h = EditorHarness(initial: (1...300).map { "Line \($0)" }.joined(separator: "\n\n"))
        var reported = 0
        h.coordinator.parent.onTopLineChange = { reported = $0 }
        h.window.layoutIfNeeded()
        let clip = h.textView.enclosingScrollView!.contentView
        clip.scroll(to: NSPoint(x: 0, y: 3000))
        h.coordinator.reportTopLine()
        #expect(reported > 50)
        #expect(h.textView.textLayoutManager != nil)   // still TextKit 2
    }
}
