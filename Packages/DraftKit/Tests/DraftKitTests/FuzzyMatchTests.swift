import Testing
@testable import DraftKit

@Suite struct FuzzyMatchTests {
    @Test func matchesSubsequences() {
        #expect(FuzzyMatch.score("dw", in: "Draft Writer") != nil)
        #expect(FuzzyMatch.score("drft", in: "Draft Writer") != nil)
        #expect(FuzzyMatch.score("", in: "Anything") == 0)
    }

    @Test func rejectsNonSubsequences() {
        #expect(FuzzyMatch.score("wd", in: "Draft Writer") == nil)
        #expect(FuzzyMatch.score("xyz", in: "Draft Writer") == nil)
        #expect(FuzzyMatch.score("drafts", in: "Draft") == nil)
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(FuzzyMatch.score("cafe", in: "Café Notes") != nil)
        #expect(FuzzyMatch.score("CAFÉ", in: "cafe notes") != nil)
        #expect(FuzzyMatch.score("malmo", in: "Malmö trip") != nil)
    }

    @Test func prefixBeatsMiddle() throws {
        let prefix = try #require(FuzzyMatch.score("not", in: "Notes"))
        let middle = try #require(FuzzyMatch.score("not", in: "Annotated"))
        #expect(prefix > middle)
    }

    @Test func consecutiveBeatsScattered() throws {
        let consecutive = try #require(FuzzyMatch.score("plan", in: "a plan b"))
        let scattered = try #require(FuzzyMatch.score("plan", in: "a pxlxaxn"))
        #expect(consecutive > scattered)
    }

    @Test func wordStartsBeatInnerLetters() throws {
        let wordStarts = try #require(FuzzyMatch.score("mn", in: "x meeting notes"))
        let inner = try #require(FuzzyMatch.score("mn", in: "x ammonia"))
        #expect(wordStarts > inner)
    }

    @Test func picksTheBestAlignmentNotTheFirst() throws {
        // A greedy match would take the "o" in "follow" and miss the word start of "outline".
        let best = try #require(FuzzyMatch.score("ou", in: "follow outline"))
        let greedyOnly = try #require(FuzzyMatch.score("ou", in: "follow xu"))
        #expect(best > greedyOnly)
    }

    @Test func rankOrdersByScoreAndDropsNonMatches() {
        let names = ["Annotated", "Grocery list", "Notes", "Meeting notes"]
        #expect(FuzzyMatch.rank(names, by: "not", key: { $0 }) == ["Notes", "Meeting notes", "Annotated"])
    }

    @Test func rankKeepsOrderForEmptyQuery() {
        let names = ["b", "a", "c"]
        #expect(FuzzyMatch.rank(names, by: "", key: { $0 }) == names)
    }

    @Test func rankPrefersShorterNamesOnTies() {
        #expect(FuzzyMatch.rank(["Draft two", "Draft"], by: "draft", key: { $0 }) == ["Draft", "Draft two"])
    }
}
