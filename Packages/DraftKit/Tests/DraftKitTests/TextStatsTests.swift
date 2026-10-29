import Testing
@testable import DraftKit

@Suite struct TextStatsTests {
    @Test func emptyText() {
        #expect(TextStats.compute("") == TextStats(words: 0, characters: 0, readingMinutes: 0))
    }

    @Test func countsWords() {
        let stats = TextStats.compute("Hello, world. This is Draft.")
        #expect(stats.words == 5)
        #expect(stats.characters == 28)
    }

    @Test func countsSwedish() {
        #expect(TextStats.compute("Det här är en mening på svenska.").words == 7)
    }

    @Test func ignoresMarkdownPunctuation() {
        #expect(TextStats.compute("# Title\n\n- one *two*").words == 3)
    }

    @Test func readingTimeRoundsUp() {
        #expect(TextStats.compute(String(repeating: "word ", count: 239)).readingMinutes == 2)
        #expect(TextStats.compute(String(repeating: "word ", count: 238)).readingMinutes == 1)
        #expect(TextStats.compute("word").readingMinutes == 1)
    }

    @Test func charactersCountGraphemes() {
        #expect(TextStats.compute("👋🏽å").characters == 2)
    }

    @Test func countsSentences() {
        #expect(TextStats.compute("One here. Two here! Three here?").sentences == 3)
        #expect(TextStats.compute("A paragraph.\n\nAnother one.").sentences == 2)
        #expect(TextStats.compute("# Title\n\nSome text. More.\n\n- item one\n- item two\n\n\n").sentences == 5)
    }

    @Test func abbreviationsDoNotSplitSentences() {
        #expect(TextStats.compute("Mr. Smith went to Washington. He liked it.").sentences == 2)
    }

    @Test func emptyOrBlankTextHasNoSentences() {
        #expect(TextStats.compute("").sentences == 0)
        #expect(TextStats.compute(" \n\t \n").sentences == 0)
    }

    @Test func textWithoutFinalPunctuationIsOneSentence() {
        #expect(TextStats.compute("just a fragment").sentences == 1)
    }

    @Test func countsSentencesInOtherLanguages() {
        #expect(TextStats.compute("Det här är en mening. Här är en till.").sentences == 2)
        #expect(TextStats.compute("Hola. ¿Qué tal? Muy bien.").sentences == 3)
    }

    @Test func charactersWithoutSpacesSkipWhitespaceAndNewlines() {
        let stats = TextStats.compute("a b\tc\nd\r\ne  ")
        #expect(stats.characters == 11)   // "\r\n" is one grapheme
        #expect(stats.charactersWithoutSpaces == 5)
    }

    @Test func charactersWithoutSpacesCountGraphemes() {
        #expect(TextStats.compute("👋🏽 å ä\u{00A0}ö").charactersWithoutSpaces == 4)
    }

    @Test func blankTextHasNoCharactersWithoutSpaces() {
        #expect(TextStats.compute(" \n\t").charactersWithoutSpaces == 0)
    }
}
