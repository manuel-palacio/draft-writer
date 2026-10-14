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
}
