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

    @Test func cacheIsBoundedByCharacters() {
        let highlighter = SyntaxHighlighter(cacheCharacterLimit: 1_000)
        // Every keystroke in a long paragraph adds a new version of it; the cache must not keep them all.
        var text = String(repeating: "The fox runs. ", count: 3)   // 42 characters, cacheable
        for _ in 0..<50 {
            text += "a"
            _ = highlighter.highlights(in: text, range: NSRange(location: 0, length: 1), excluding: [])
            #expect(highlighter.cachedCharacters <= 1_000)
        }
    }

    @Test func hugeParagraphIsNotCached() {
        let highlighter = SyntaxHighlighter(cacheCharacterLimit: 1_000)
        let text = String(repeating: "The fox runs. ", count: 20)   // 280 characters, over a tenth of the budget
        _ = highlighter.highlights(in: text, range: NSRange(location: 0, length: 1), excluding: [])
        #expect(highlighter.cachedCharacters == 0)
    }

    @Test func missingModelIsNotCached() {
        var supported = false
        let highlighter = SyntaxHighlighter(isSupported: { _ in supported })
        let text = "The quick fox jumps quietly and happily."
        let all = NSRange(location: 0, length: (text as NSString).length)
        #expect(highlighter.highlights(in: text, range: all, excluding: []).isEmpty)
        supported = true   // the model finished downloading
        #expect(!highlighter.highlights(in: text, range: all, excluding: []).isEmpty)
    }

    @Test func missingLanguagesAreFoundPerParagraph() {
        let highlighter = SyntaxHighlighter(isSupported: { $0 == .english })
        let text = """
        The weather was lovely this morning, so we walked along the river for an hour.

        Nous avons mangé une excellente soupe à l'oignon dans un petit restaurant du quartier.

        Wir sind danach mit dem Zug nach Hause gefahren und haben lange geschlafen.
        """
        _ = highlighter.highlights(in: text, range: NSRange(location: 0, length: (text as NSString).length), excluding: [])
        #expect(highlighter.missingLanguages == [.french, .german])
    }

    @Test func needsAssetsIsNilForEnglish() {
        let highlighter = SyntaxHighlighter()
        _ = highlighter.highlights(in: "The quick fox jumps over the lazy dog.", range: NSRange(location: 0, length: 1), excluding: [])
        #expect(highlighter.missingLanguages.isEmpty)
    }
}
