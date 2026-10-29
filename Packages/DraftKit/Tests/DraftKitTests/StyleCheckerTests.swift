import Foundation
import Testing
@testable import DraftKit

@Suite struct StyleCheckerTests {
    func matched(_ paragraph: String) -> [String: StyleCheck] {
        Dictionary(StyleChecker.matches(in: paragraph).map { ((paragraph as NSString).substring(with: $0.range), $0.check) },
                   uniquingKeysWith: { first, _ in first })
    }

    @Test func singleWordFillers() {
        #expect(matched("It was really very good.") == ["really": .filler, "very": .filler])
    }

    @Test func multiWordPhrases() {
        let m = matched("At the end of the day it was an added bonus.")
        #expect(m["At the end of the day"] == .cliche)
        #expect(m["added bonus"] == .redundancy)
    }

    @Test func caseInsensitive() {
        #expect(matched("JUST think Outside The Box.") == ["JUST": .filler, "think Outside The Box": .cliche])
    }

    @Test func wholeWordsOnly() {
        #expect(matched("Justice is veryfied, adjust it.").isEmpty)
    }

    @Test func phraseSpansSingleWhitespaceOnly() {
        #expect(matched("an end\u{2028}result")["end\u{2028}result"] == .redundancy)
        #expect(matched("the end  result").isEmpty)
        #expect(matched("the end, result").isEmpty)
    }

    @Test func longestMatchWins() {
        // "each and every" is a redundancy; nothing shorter inside it may be reported separately.
        let matches = StyleChecker.matches(in: "We checked each and every one.")
        #expect(matches.count == 1)
        #expect(matches.first?.check == .redundancy)
        #expect(matches.first?.range == ("We checked each and every one." as NSString).range(of: "each and every"))
    }

    @Test func curlyApostrophesMatch() {
        #expect(matched("It’s a no-brainer.")["no-brainer"] == .cliche)
    }

    @Test func listsAreNonEmptyAndLowercase() {
        for check in StyleCheck.allCases {
            #expect(!StyleChecker.phrases(for: check).isEmpty)
            #expect(StyleChecker.phrases(for: check).allSatisfy { $0 == $0.lowercased() })
        }
    }
}

@Suite struct HighlighterStyleCheckTests {
    func styleMatches(_ text: String, excluding: [NSRange] = []) -> [StyleMatch] {
        SyntaxHighlighter().styleMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                         excluding: excluding)
    }

    @Test func englishParagraphIsChecked() {
        let text = "Intro.\n\nIt was basically the end result of a long day."
        let matches = styleMatches(text)
        #expect(matches.contains { $0.range == (text as NSString).range(of: "basically") && $0.check == .filler })
        #expect(matches.contains { $0.range == (text as NSString).range(of: "end result") && $0.check == .redundancy })
    }

    @Test func nonEnglishParagraphYieldsNothing() {
        // "just" appears, but the paragraph is Swedish; pretend it has a tagging model so only the language gates.
        let text = "Det var just en mycket fin dag vid sjön och vi badade länge i det varma vattnet."
        let matches = SyntaxHighlighter(isSupported: { _ in true })
            .styleMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), excluding: [])
        #expect(StyleChecker.matches(in: text).count == 1)
        #expect(matches.isEmpty)
    }

    @Test func codeIsExcluded() {
        let text = "Run `really fast` now, it is really quick."
        let code = (text as NSString).range(of: "`really fast`")
        let matches = styleMatches(text, excluding: [code])
        #expect(matches.count == 1)
        #expect(matches.allSatisfy { NSIntersectionRange($0.range, code).length == 0 })
    }
}
