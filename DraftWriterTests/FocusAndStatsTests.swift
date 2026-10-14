import AppKit
import DraftKit
import Foundation
import Testing
@testable import Draft_Writer

@MainActor
@Suite struct FocusAndStatsTests {
    /// Foreground colour set as a TextKit 2 rendering attribute at `location`, if any.
    func renderingColor(_ h: EditorHarness, at location: Int) -> NSColor? {
        guard let tlm = h.textView.textLayoutManager,
              let start = tlm.location(tlm.documentRange.location, offsetBy: location) else { return nil }
        var color: NSColor?
        tlm.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            if range.contains(start) || range.location.compare(start) == .orderedSame {
                color = attributes[.foregroundColor] as? NSColor
            }
            return false
        }
        return color
    }

    @Test func sentenceFocusDimsOtherSentences() {
        let h = EditorHarness(initial: "One here. Two here.")
        h.coordinator.parent.focusMode = .sentence
        h.textView.setSelectedRange(NSRange(location: 12, length: 0))
        h.coordinator.applyFocus()
        #expect(renderingColor(h, at: 0) == Theme.dimmed)
        #expect(renderingColor(h, at: 12) == nil)
    }

    @Test func focusOffClearsDimming() {
        let h = EditorHarness(initial: "One here. Two here.")
        h.coordinator.parent.focusMode = .sentence
        h.coordinator.applyFocus()
        h.coordinator.parent.focusMode = .off
        h.coordinator.applyFocus()
        #expect(renderingColor(h, at: 0) == nil)
    }

    @Test func typewriterCentresWithHalfHeightInsets() {
        let h = EditorHarness(initial: String(repeating: "line\n", count: 200))
        h.textView.typewriter = true
        let visible = h.textView.enclosingScrollView!.contentSize.height
        #expect(h.textView.textContainerInset.height == (visible / 2).rounded())
        h.textView.typewriter = false
        #expect(h.textView.textContainerInset.height == 40)
    }

    @Test func footerLabelFormatsCounts() {
        let stats = TextStats(words: 1234, characters: 7890, readingMinutes: 6)
        #expect(StatsFooter.label(for: stats, locale: Locale(identifier: "en_US")) == "1,234 words · 7,890 characters · 6 min")
    }

    @Test func footerLabelSingular() {
        let stats = TextStats(words: 1, characters: 1, readingMinutes: 1)
        #expect(StatsFooter.label(for: stats, locale: Locale(identifier: "en_US")) == "1 word · 1 character · 1 min")
    }
}
