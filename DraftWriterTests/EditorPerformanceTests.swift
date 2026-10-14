import AppKit
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

    @Test func typingInLongDocument() {
        let h = EditorHarness(initial: Self.longText)
        h.textView.setSelectedRange(NSRange(location: (Self.longText as NSString).length / 2, length: 0))
        let ms = milliseconds { h.type("x") }
        #expect(ms < 50, "one keystroke took \(ms) ms")
    }
}
