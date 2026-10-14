import Foundation
import NaturalLanguage

/// Word count, character count and reading time for a piece of text.
public struct TextStats: Equatable, Sendable {
    public static let wordsPerMinute = 238

    public let words: Int
    public let characters: Int
    public let readingMinutes: Int

    public init(words: Int, characters: Int, readingMinutes: Int) {
        self.words = words
        self.characters = characters
        self.readingMinutes = readingMinutes
    }

    public static func compute(_ text: String) -> TextStats {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let words = tokenizer.tokens(for: text.startIndex..<text.endIndex).count
        let minutes = (words + wordsPerMinute - 1) / wordsPerMinute
        return TextStats(words: words, characters: text.count, readingMinutes: minutes)
    }
}
