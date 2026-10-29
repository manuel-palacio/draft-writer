import AppKit
import DraftKit
import Foundation
import Testing
@testable import Draft_Writer

/// The spec's typing-latency and re-style budgets, measured in the real editor
/// (where the text is a bridged NSTextStorage string, unlike the DraftKit tests).
@MainActor
@Suite struct EditorPerformanceTests {
    static let longText: String = {
        let paragraph = "The *quiet* writer opens a **draft** and reads one `sentence` at a time, then [another](https://x.io) one.\n\n"
        let section = "## Section\n\n" + String(repeating: paragraph, count: 10) + "```\nlet a = 1\n```\n\n- one\n- two\n\n"
        return String(repeating: section, count: 340)   // ≈ 56,000 words
    }()

    func milliseconds(_ body: () -> Void) -> Double {
        let elapsed = ContinuousClock().measure(body)
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    @Test func fullRestyleOfLongDocument() {
        let h = EditorHarness(initial: Self.longText)
        let ms = milliseconds { h.coordinator.restyleAll() }
        #expect(ms < 1000, "full restyle took \(ms) ms")
    }

    @Test func typingInLongDocumentWithHighlighting() {
        let h = EditorHarness(initial: Self.longText)
        h.coordinator.parent.highlightClasses = Set(LexicalClass.allCases)
        h.textView.setSelectedRange(NSRange(location: (Self.longText as NSString).length / 2, length: 0))
        h.coordinator.applyRenderingColors()   // warm the paragraph cache, as scrolling there would
        let ms = milliseconds { h.type("x") }
        #expect(ms < 50, "one keystroke with highlighting took \(ms) ms")
    }

    /// Arrow keys and clicks recolour without editing: only the ranges coloured last time are cleared.
    @Test func movingTheCaretInLongDocumentWithFocusAndHighlighting() {
        let h = EditorHarness(initial: Self.longText)
        h.coordinator.parent.focusMode = .sentence
        h.coordinator.parent.highlightClasses = Set(LexicalClass.allCases)
        let middle = (Self.longText as NSString).length / 2
        h.textView.setSelectedRange(NSRange(location: middle, length: 0))   // warms the paragraph cache
        let ms = milliseconds {
            for offset in 1...10 { h.textView.setSelectedRange(NSRange(location: middle + offset * 40, length: 0)) }
        } / 10
        #expect(ms < 20, "one caret move took \(ms) ms")
    }

    @Test func typingInLongDocument() {
        let h = EditorHarness(initial: Self.longText)
        h.textView.setSelectedRange(NSRange(location: (Self.longText as NSString).length / 2, length: 0))
        let ms = milliseconds { h.type("x") }
        #expect(ms < 50, "one keystroke took \(ms) ms")
    }
}
