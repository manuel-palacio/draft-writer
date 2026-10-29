import Foundation
import NaturalLanguage

/// Word, sentence and character counts and reading time for a piece of text.
public struct TextStats: Equatable, Sendable {
    public static let wordsPerMinute = 238

    public let words: Int
    public let sentences: Int
    public let characters: Int
    public let charactersWithoutSpaces: Int
    public let readingMinutes: Int

    public init(words: Int, sentences: Int = 0, characters: Int, charactersWithoutSpaces: Int = 0, readingMinutes: Int) {
        self.words = words
        self.sentences = sentences
        self.characters = characters
        self.charactersWithoutSpaces = charactersWithoutSpaces
        self.readingMinutes = readingMinutes
    }

    public static func compute(_ text: String) -> TextStats {
        let words = countWords(in: text)
        let (characters, nonBlank) = countCharacters(in: text)
        let minutes = (words + wordsPerMinute - 1) / wordsPerMinute
        return TextStats(words: words, sentences: countSentences(in: text),
                         characters: characters, charactersWithoutSpaces: nonBlank, readingMinutes: minutes)
    }

    public static func countWords(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).count
    }

    /// The tokenizer reports each blank line between paragraphs as a sentence of its own; those don't count.
    private static func countSentences(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if text[range].contains(where: { !$0.isWhitespace }) { count += 1 }
            return true
        }
        return count
    }

    /// Both counts in one pass over the grapheme clusters, which dominates on long documents.
    private static func countCharacters(in text: String) -> (all: Int, nonBlank: Int) {
        var all = 0, nonBlank = 0
        for character in text {
            all += 1
            if !character.isWhitespace { nonBlank += 1 }
        }
        return (all, nonBlank)
    }
}
