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

@MainActor
@Suite struct CodeRangeShiftTests {
    typealias C = EditorView.Coordinator

    @Test func deletionIntoCodeKeepsTheRestOfTheCode() {
        // "abc `code` x" with `code` at {4,6}; deleting {2,4} leaves "ode`" at {2,4}.
        #expect(C.shift([NSRange(location: 4, length: 6)], replacing: NSRange(location: 2, length: 4), with: 0)
                == [NSRange(location: 2, length: 4)])
    }

    @Test func insertionBeforeShifts() {
        #expect(C.shift([NSRange(location: 4, length: 6)], replacing: NSRange(location: 1, length: 0), with: 3)
                == [NSRange(location: 7, length: 6)])
    }

    @Test func editInsideResizes() {
        #expect(C.shift([NSRange(location: 4, length: 6)], replacing: NSRange(location: 6, length: 1), with: 3)
                == [NSRange(location: 4, length: 8)])
    }

    @Test func deletionCoveringCodeCollapsesIt() {
        #expect(C.shift([NSRange(location: 4, length: 6)], replacing: NSRange(location: 2, length: 10), with: 0)
                == [NSRange(location: 2, length: 0)])
    }

    @Test func editAfterIsIgnored() {
        #expect(C.shift([NSRange(location: 4, length: 6)], replacing: NSRange(location: 11, length: 1), with: 0)
                == [NSRange(location: 4, length: 6)])
    }
}
