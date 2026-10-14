import AppKit
import Testing
@testable import Draft_Writer

@MainActor
@Suite struct StylingRegressionTests {
    @Test func typingInsideFencedCodeKeepsCodeStyle() {
        let text = "Intro\n\n```\n# not heading\n\nx\n```\n"
        let h = EditorHarness(initial: text)
        let x = (text as NSString).range(of: "x\n```").location
        h.textView.setSelectedRange(NSRange(location: x + 1, length: 0))
        h.type("y")
        let hash = (text as NSString).range(of: "# not").location
        #expect(h.font(at: hash)?.fontName == "iAWriterMonoS-Regular")
        #expect(h.font(at: x)?.fontName == "iAWriterMonoS-Regular")
    }

    @Test func listItemsHaveHangingIndent() throws {
        let h = EditorHarness(initial: "- a long list item that wraps")
        let style = try #require(h.textView.textStorage?.attribute(.paragraphStyle, at: 3, effectiveRange: nil) as? NSParagraphStyle)
        let markerWidth = ("- " as NSString).size(withAttributes: [.font: Theme.font(.duo, size: 17)]).width
        #expect(abs(style.headIndent - markerWidth) < 0.5)
        #expect(style.firstLineHeadIndent == 0)
    }
}
