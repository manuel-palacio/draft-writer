import AppKit
import DraftKit
import Testing
@testable import Draft_Writer

@MainActor
@Suite struct HighlightTests {
    func renderingColor(_ h: EditorHarness, at location: Int) -> NSColor? {
        guard let tlm = h.textView.textLayoutManager,
              let start = tlm.location(tlm.documentRange.location, offsetBy: location) else { return nil }
        var color: NSColor?
        tlm.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            if range.contains(start) { color = attributes[.foregroundColor] as? NSColor }
            return false
        }
        return color
    }

    func offset(of word: String, in h: EditorHarness) -> Int {
        (h.textView.string as NSString).range(of: word).location
    }

    func harness(_ text: String, classes: Set<LexicalClass> = Set(LexicalClass.allCases)) -> EditorHarness {
        let h = EditorHarness(initial: text)
        h.coordinator.parent.highlightClasses = classes
        h.coordinator.applyRenderingColors()
        return h
    }

    @Test func highlightsColourWords() {
        let h = harness("The quick fox jumps over the dog.")
        #expect(renderingColor(h, at: offset(of: "fox", in: h)) === Theme.highlight(.noun, dimmed: false))
        #expect(renderingColor(h, at: offset(of: "jumps", in: h)) === Theme.highlight(.verb, dimmed: false))
    }

    @Test func focusKeepsHue() {
        let h = EditorHarness(initial: "One fox sleeps here. Two dogs run there.")
        h.coordinator.parent.highlightClasses = Set(LexicalClass.allCases)
        h.coordinator.parent.focusMode = .sentence
        h.textView.setSelectedRange(NSRange(location: offset(of: "dogs", in: h), length: 0))
        h.coordinator.applyRenderingColors()
        #expect(renderingColor(h, at: offset(of: "fox", in: h)) === Theme.highlight(.noun, dimmed: true))
        #expect(renderingColor(h, at: offset(of: "dogs", in: h)) === Theme.highlight(.noun, dimmed: false))
        #expect(renderingColor(h, at: offset(of: "One", in: h)) === Theme.dimmed)
    }

    @Test func codeIsNotHighlighted() {
        let h = harness("Use the `fox` command now, quickly.")
        #expect(renderingColor(h, at: offset(of: "fox", in: h)) == nil)
        #expect(renderingColor(h, at: offset(of: "command", in: h)) != nil)
    }

    @Test func disabledClassIsPlain() {
        let h = harness("The quick fox jumps over the dog.", classes: [.verb])
        #expect(renderingColor(h, at: offset(of: "fox", in: h)) == nil)
        #expect(renderingColor(h, at: offset(of: "jumps", in: h)) === Theme.highlight(.verb, dimmed: false))
    }

    @Test func highlightingOffClearsColours() {
        let h = harness("The quick fox jumps over the dog.")
        h.coordinator.parent.highlightClasses = []
        h.coordinator.applyRenderingColors()
        #expect(renderingColor(h, at: offset(of: "fox", in: h)) == nil)
    }

    @Test func recoloursWhenWindowGrows() {
        // A window opens tiny and then takes its real size; words that become visible must be coloured
        // without the user having to scroll first.
        let text = (1...12).map { "Line \($0) has a fox." }.joined(separator: "\n\n") + "\n\nThe last dog sleeps."
        let h = EditorHarness(initial: text)
        h.window.setContentSize(NSSize(width: 400, height: 30))
        h.coordinator.parent.highlightClasses = Set(LexicalClass.allCases)
        h.coordinator.applyRenderingColors()
        #expect(renderingColor(h, at: offset(of: "dog", in: h)) == nil)
        h.window.setContentSize(NSSize(width: 800, height: 900))
        h.window.contentView?.layoutSubtreeIfNeeded()
        #expect(renderingColor(h, at: offset(of: "dog", in: h)) === Theme.highlight(.noun, dimmed: false))
    }

    func styleHarness(_ text: String, checks: Set<StyleCheck> = Set(StyleCheck.allCases),
                      classes: Set<LexicalClass> = Set(LexicalClass.allCases)) -> EditorHarness {
        let h = EditorHarness(initial: text)
        h.coordinator.parent.highlightClasses = classes
        h.coordinator.parent.styleChecks = checks
        h.coordinator.applyRenderingColors()
        return h
    }

    @Test func styleChecksColourMatchesOverPartOfSpeech() {
        let h = styleHarness("It was really an added bonus, at the end of the day.")
        #expect(renderingColor(h, at: offset(of: "really", in: h)) === Theme.highlight(.filler, dimmed: false))
        #expect(renderingColor(h, at: offset(of: "bonus", in: h)) === Theme.highlight(.redundancy, dimmed: false))
        #expect(renderingColor(h, at: offset(of: "day", in: h)) === Theme.highlight(.cliche, dimmed: false))
    }

    @Test func styleChecksWorkWithoutPartOfSpeech() {
        let h = styleHarness("The fox was very quick.", classes: [])
        #expect(renderingColor(h, at: offset(of: "very", in: h)) === Theme.highlight(.filler, dimmed: false))
        #expect(renderingColor(h, at: offset(of: "fox", in: h)) == nil)
    }

    @Test func disabledStyleCheckIsPlain() {
        let h = styleHarness("It was really an added bonus.", checks: [.redundancy], classes: [])
        #expect(renderingColor(h, at: offset(of: "really", in: h)) == nil)
        #expect(renderingColor(h, at: offset(of: "added", in: h)) === Theme.highlight(.redundancy, dimmed: false))
        h.coordinator.parent.styleChecks = []
        h.coordinator.applyRenderingColors()
        #expect(renderingColor(h, at: offset(of: "added", in: h)) == nil)
    }

    @Test func styleChecksDimOutsideFocus() {
        let h = EditorHarness(initial: "It was really late. The end result was fine.")
        h.coordinator.parent.styleChecks = Set(StyleCheck.allCases)
        h.coordinator.parent.focusMode = .sentence
        h.textView.setSelectedRange(NSRange(location: offset(of: "fine", in: h), length: 0))
        h.coordinator.applyRenderingColors()
        #expect(renderingColor(h, at: offset(of: "really", in: h)) === Theme.highlight(.filler, dimmed: true))
        #expect(renderingColor(h, at: offset(of: "result", in: h)) === Theme.highlight(.redundancy, dimmed: false))
    }

    @Test func styleChecksSkipCode() {
        let h = styleHarness("Run `really` now, it is really quick.", classes: [])
        #expect(renderingColor(h, at: offset(of: "`really`", in: h) + 1) == nil)
        #expect(renderingColor(h, at: offset(of: "is really", in: h) + 3) === Theme.highlight(.filler, dimmed: false))
    }
}
