import AppKit
import DraftKit
import Testing
@testable import Draft_Writer

@MainActor
@Suite struct HeadingJumpTests {
    static let longDocument = "# Start\n\n" + String(repeating: "A paragraph of filler text.\n\n", count: 300) + "## Target\n\nThe end.\n"

    @Test func jumpMovesTheCaretToTheHeading() throws {
        let h = EditorHarness(initial: Self.longDocument)
        let target = try #require(HeadingOutline.headings(in: h.text).last)
        h.coordinator.reveal(EditorJump(location: target.location))
        #expect(h.textView.selectedRange() == NSRange(location: target.location, length: 0))
        #expect(h.selection == NSRange(location: target.location, length: 0))
    }

    @Test func jumpScrollsTheHeadingIntoViewAndFocusesTheEditor() throws {
        let h = EditorHarness(initial: Self.longDocument)
        let target = try #require(HeadingOutline.headings(in: h.text).last)
        #expect(h.textView.visibleRect.minY == 0)
        h.coordinator.reveal(EditorJump(location: target.location))
        #expect(h.textView.visibleRect.minY > 0)
        #expect(h.window.firstResponder === h.textView)
    }

    @Test func eachJumpIsHonouredOnce() {
        let h = EditorHarness(initial: Self.longDocument)
        let jump = EditorJump(location: 2)
        h.coordinator.reveal(jump)
        #expect(h.coordinator.lastJump == jump)
        #expect(EditorJump(location: 2) != jump)   // choosing the same heading again is a new request
    }
}
