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

    @Test func strikethroughIsStruckWithGreyedMarkers() {
        let h = EditorHarness(initial: "a ~~gone~~ b")
        let struck = h.textView.textStorage?.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) as? Int
        #expect(struck == NSUnderlineStyle.single.rawValue)
        #expect(h.color(at: 2) == Theme.marker)
        #expect(h.color(at: 8) == Theme.marker)
        #expect(h.color(at: 5) == Theme.text)
    }

    @Test func imagesTablesAndBreaksAreGreyed() {
        let text = "![alt](a.png)\n\n---\n\n| A |\n|---|\n"
        let h = EditorHarness(initial: text)
        let ns = text as NSString
        for marker in ["!", "a.png", "---\n\n", "|---|"] {
            #expect(h.color(at: ns.range(of: marker).location) == Theme.marker, "\(marker)")
        }
        #expect(h.color(at: 2) == Theme.text)   // the alt text
    }

    @Test func wikilinksAndTagsAreStyled() {
        let text = "See [[Note]] #idea"
        let h = EditorHarness(initial: text)
        let underline = h.textView.textStorage?.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int
        #expect(underline == NSUnderlineStyle.single.rawValue)
        #expect(h.color(at: 4) == Theme.marker)   // [[
        #expect(h.color(at: (text as NSString).range(of: "#idea").location) == Theme.link)
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

    @Test func insertionAtStartShiftsTheRange() {
        #expect(C.shift([NSRange(location: 4, length: 6)], replacing: NSRange(location: 4, length: 0), with: 2)
                == [NSRange(location: 6, length: 6)])
    }

    @Test func insertionAtEndDoesNotExtendTheRange() {
        // Text typed right after a closing backtick is not code.
        #expect(C.shift([NSRange(location: 4, length: 6)], replacing: NSRange(location: 10, length: 0), with: 2,
                        documentLength: 20) == [NSRange(location: 4, length: 6)])
    }

    @Test func typingAtTheEndOfAnUnclosedFenceStaysCode() {
        // "```\nlet x" with no closing fence: the code block runs to the end of the document.
        #expect(C.shift([NSRange(location: 0, length: 9)], replacing: NSRange(location: 9, length: 0), with: 3,
                        documentLength: 9) == [NSRange(location: 0, length: 12)])
    }

    @Test func editAfterIsIgnored() {
        #expect(C.shift([NSRange(location: 4, length: 6)], replacing: NSRange(location: 11, length: 1), with: 0)
                == [NSRange(location: 4, length: 6)])
    }
}
