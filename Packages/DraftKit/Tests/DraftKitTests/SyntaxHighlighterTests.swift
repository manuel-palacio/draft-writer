import Foundation
import Testing
@testable import DraftKit

@Suite struct SyntaxHighlighterTests {
    func classes(_ text: String, excluding: [NSRange] = []) -> [String: LexicalClass] {
        let highlights = SyntaxHighlighter().highlights(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                                        excluding: excluding)
        return Dictionary(highlights.map { ((text as NSString).substring(with: $0.range), $0.lexicalClass) },
                          uniquingKeysWith: { first, _ in first })
    }

    @Test func englishClasses() {
        let c = classes("The quick fox jumps quietly and happily.")
        #expect(c["fox"] == .noun)
        #expect(c["jumps"] == .verb)
        #expect(c["quick"] == .adjective)
        #expect(c["quietly"] == .adverb)
        #expect(c["and"] == .conjunction)
    }

    @Test func swedishIsUncoloured() {
        #expect(classes("Det lilla huset står vid den blå sjön och vi älskar det.").isEmpty)
    }

    @Test func skipsExcludedRanges() {
        let text = "Use the `fast` path every day."
        let code = (text as NSString).range(of: "`fast`")
        let highlights = SyntaxHighlighter().highlights(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                                        excluding: [code])
        #expect(!highlights.isEmpty)
        #expect(highlights.allSatisfy { NSIntersectionRange($0.range, code).length == 0 })
    }

    @Test func rangeIsWidenedToParagraph() {
        let text = "The quick fox jumps quietly."
        let jumps = (text as NSString).range(of: "jumps")
        let highlights = SyntaxHighlighter().highlights(in: text, range: jumps, excluding: [])
        #expect(highlights.contains { (text as NSString).substring(with: $0.range) == "fox" })
    }

    @Test func rangesAreAbsolute() {
        let text = "Intro.\n\nThe fox runs far."
        let second = (text as NSString).range(of: "The fox runs far.")
        let highlights = SyntaxHighlighter().highlights(in: text, range: second, excluding: [])
        let fox = (text as NSString).range(of: "fox")
        #expect(highlights.contains { $0.range == fox && $0.lexicalClass == .noun })
    }

    @Test func cacheReturnsSameResult() {
        let highlighter = SyntaxHighlighter()
        let text = "The quick fox jumps quietly and happily."
        let all = NSRange(location: 0, length: (text as NSString).length)
        #expect(highlighter.highlights(in: text, range: all, excluding: []) == highlighter.highlights(in: text, range: all, excluding: []))
    }

    @Test func needsAssetsIsNilForEnglish() {
        #expect(SyntaxHighlighter.needsAssets("The quick fox jumps over the lazy dog.") == nil)
    }
}
