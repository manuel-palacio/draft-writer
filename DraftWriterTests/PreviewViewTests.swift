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
        preview.scheduleUpdate(markdown: "# B")
        let first = preview.updateTask
        preview.scheduleUpdate(markdown: "# C")
        #expect(first?.isCancelled == true)   // one pending render at a time
        await preview.updateTask?.value
        #expect(try await text(preview, "#content h1") == "C")
        #expect(preview.pageLoads == 1)
    }

    @Test func reloadsAfterWebProcessCrash() async throws {
        let preview = PreviewView.Coordinator()
        preview.show(markdown: "# A")
        await preview.waitUntilLoaded()
        preview.lastMarkdown = "# After"
        preview.webViewWebContentProcessDidTerminate(preview.webView)
        await preview.waitUntilLoaded()
        #expect(try await text(preview, "#content h1") == "After")
        #expect(preview.pageLoads == 2)
    }

    @Test func stopsReloadingWhenThePageKeepsCrashing() async throws {
        let preview = PreviewView.Coordinator()
        preview.lastMarkdown = "# Heavy"
        preview.show(markdown: "# Heavy")
        await preview.waitUntilLoaded()
        for _ in 0..<5 {
            preview.webViewWebContentProcessDidTerminate(preview.webView)
            await preview.waitUntilLoaded()
        }
        #expect(preview.pageLoads == 3)   // the first load and two retries, then it gives up
        #expect(try await text(preview, "body")?.contains("crashed") == true)
        preview.lastMarkdown = "# Lighter"
        preview.show(markdown: "# Lighter")   // a new edit tries again
        await preview.waitUntilLoaded()
        #expect(try await text(preview, "#content h1") == "Lighter")
    }

    @Test func usesChosenFont() async throws {
        let preview = PreviewView.Coordinator()
        preview.font = .quattro
        preview.show(markdown: "Hello")
        await preview.waitUntilLoaded()
        var family = try await preview.webView.evaluateJavaScript("getComputedStyle(document.body).fontFamily") as? String
        #expect(family?.contains("Quattro") == true)
        preview.font = .mono
        family = try await preview.webView.evaluateJavaScript("getComputedStyle(document.body).fontFamily") as? String
        #expect(family?.contains("iA Writer Mono") == true)
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

    @Test func onlyWebLinksOpenExternally() {
        #expect(PreviewView.Coordinator.opensExternally(URL(string: "https://example.com")!))
        #expect(PreviewView.Coordinator.opensExternally(URL(string: "mailto:a@b.c")!))
        #expect(!PreviewView.Coordinator.opensExternally(URL(string: "draft-asset://doc/#intro")!))
        #expect(!PreviewView.Coordinator.opensExternally(URL(string: "draft-asset://doc/other.md")!))
    }

    @Test func linkClicksOpenExternally() {
        #expect(PreviewView.Coordinator.policy(for: StubAction(.linkActivated)) == .cancel)
        #expect(PreviewView.Coordinator.policy(for: StubAction(.other)) == .allow)
    }
}

@MainActor
@Suite struct EditorTopLineTests {
    @Test func reportsTopVisibleLineOnScroll() async {
        let h = EditorHarness(initial: (1...300).map { "Line \($0)" }.joined(separator: "\n\n"))
        var reported = 0
        h.coordinator.parent.onTopLineChange = { reported = $0 }
        h.window.layoutIfNeeded()
        let clip = h.textView.enclosingScrollView!.contentView
        clip.scroll(to: NSPoint(x: 0, y: 3000))
        h.coordinator.reportTopLine()
        await Task.yield()
        #expect(reported > 50)
        clip.scroll(to: NSPoint(x: 0, y: 0))
        h.coordinator.reportTopLine()
        await Task.yield()
        #expect(reported == 1)
        #expect(h.textView.textLayoutManager != nil)   // still TextKit 2
    }

    @Test func topLineReportsAreCheapOnHugeDocuments() {
        let h = EditorHarness(initial: (1...40_000).map { "Line \($0) of a long document." }.joined(separator: "\n\n"))
        h.coordinator.parent.onTopLineChange = { _ in }
        h.window.layoutIfNeeded()
        let clip = h.textView.enclosingScrollView!.contentView
        clip.scroll(to: NSPoint(x: 0, y: 200_000))
        h.coordinator.reportTopLine()   // builds the line index once
        let elapsed = ContinuousClock().measure {
            for step in 0..<50 {
                clip.scroll(to: NSPoint(x: 0, y: 200_000 + step * 40))
                h.coordinator.reportTopLine()
            }
        }
        #expect(elapsed < .milliseconds(100))
    }
}
