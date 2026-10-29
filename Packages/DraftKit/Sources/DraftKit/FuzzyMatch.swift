import Foundation

/// Subsequence matching for Quick Open and Jump to Heading: every query character must appear in order.
/// Matches at the start, at word starts and in runs score higher. Case and diacritics are ignored.
public enum FuzzyMatch {
    static let matchScore = 1
    static let wordStartBonus = 8
    static let prefixBonus = 12
    /// Above `wordStartBonus`, so "draft" matches "Draft two" as one run rather than jumping to "two".
    static let consecutiveBonus = 10

    /// The best alignment's score, or nil when `query` is not a subsequence of `candidate`. Empty queries score 0.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(fold(query))
        let haystack = Array(fold(candidate))
        guard !needle.isEmpty else { return 0 }
        guard needle.count <= haystack.count else { return nil }
        var previous = firstCharacterScores(needle[0], in: haystack)
        for character in needle.dropFirst() {
            previous = nextCharacterScores(character, in: haystack, after: previous)
        }
        return previous.compactMap { $0 }.max()
    }

    /// The items that match, best first; ties go to the shorter key, then to the original order.
    /// An empty query keeps every item in its original order.
    public static func rank<Item>(_ items: [Item], by query: String, key: (Item) -> String) -> [Item] {
        guard !query.isEmpty else { return items }
        let scored = items.enumerated().compactMap { index, item -> (item: Item, score: Int, length: Int, index: Int)? in
            let name = key(item)
            return score(query, in: name).map { (item, $0, name.count, index) }
        }
        return scored.sorted { a, b in
            (b.score, a.length, a.index) < (a.score, b.length, b.index)
        }.map(\.item)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Scores for the query's first character matched at each haystack position (nil where it doesn't match).
    private static func firstCharacterScores(_ character: Character, in haystack: [Character]) -> [Int?] {
        haystack.indices.map { j in
            haystack[j] == character ? positionScore(j, in: haystack) + (j == 0 ? prefixBonus : 0) : nil
        }
    }

    /// Best scores for the next query character at each position, extending the best earlier match:
    /// either the one right before it (a run) or any one further back.
    private static func nextCharacterScores(_ character: Character, in haystack: [Character], after previous: [Int?]) -> [Int?] {
        var current = [Int?](repeating: nil, count: haystack.count)
        var bestFurtherBack: Int?
        for j in haystack.indices {
            if j >= 2, let earlier = previous[j - 2] { bestFurtherBack = max(bestFurtherBack ?? earlier, earlier) }
            guard haystack[j] == character else { continue }
            let run = j >= 1 ? previous[j - 1].map { $0 + consecutiveBonus } : nil
            guard let best = [run, bestFurtherBack].compactMap({ $0 }).max() else { continue }
            current[j] = best + positionScore(j, in: haystack)
        }
        return current
    }

    private static func positionScore(_ j: Int, in haystack: [Character]) -> Int {
        let isWordStart = j == 0 || !(haystack[j - 1].isLetter || haystack[j - 1].isNumber)
        return matchScore + (isWordStart ? wordStartBonus : 0)
    }
}
