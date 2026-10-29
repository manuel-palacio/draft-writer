import Foundation

/// Categories of weak English phrasing the editor can point out.
public enum StyleCheck: String, CaseIterable, Sendable {
    case filler, cliche, redundancy
}

public struct StyleMatch: Hashable, Sendable {
    public let range: NSRange
    public let check: StyleCheck

    public init(range: NSRange, check: StyleCheck) {
        self.range = range
        self.check = check
    }
}

/// Finds fillers, clichés and redundancies in one English paragraph from fixed word lists. Matching is
/// whole-word and case-insensitive; a phrase's words may be separated by one whitespace character, and
/// where phrases overlap the longest one starting first wins.
public enum StyleChecker {
    public static func phrases(for check: StyleCheck) -> [String] {
        switch check {
        case .filler: fillers
        case .cliche: cliches
        case .redundancy: redundancies
        }
    }

    /// Matches in `paragraph`, with ranges relative to it (UTF-16).
    public static func matches(in paragraph: String) -> [StyleMatch] {
        let words = words(in: paragraph)
        let ns = paragraph as NSString
        var result: [StyleMatch] = []
        var index = 0
        while index < words.count {
            if let phrase = longestPhrase(at: index, in: words, ns) {
                let last = words[index + phrase.words.count - 1].range
                result.append(StyleMatch(range: NSUnionRange(words[index].range, last), check: phrase.check))
                index += phrase.words.count
            } else {
                index += 1
            }
        }
        return result
    }

    private struct Phrase {
        let words: [String]
        let check: StyleCheck
    }

    private struct Word {
        let text: String
        let range: NSRange
    }

    /// Phrases by first word, longest first, so the first one that fits is the longest.
    private static let phrasesByFirstWord: [String: [Phrase]] = {
        let all = StyleCheck.allCases.flatMap { check in
            phrases(for: check).map { Phrase(words: $0.split(separator: " ").map(String.init), check: check) }
        }
        return Dictionary(grouping: all, by: { $0.words[0] }).mapValues { $0.sorted { $0.words.count > $1.words.count } }
    }()

    private static func longestPhrase(at index: Int, in words: [Word], _ ns: NSString) -> Phrase? {
        phrasesByFirstWord[words[index].text]?.first { phrase in
            guard index + phrase.words.count <= words.count else { return false }
            return phrase.words.indices.allSatisfy { offset in
                let word = words[index + offset]
                return word.text == phrase.words[offset]
                    && (offset == 0 || isSingleWhitespace(between: words[index + offset - 1], and: word, ns))
            }
        }
    }

    private static func isSingleWhitespace(between previous: Word, and next: Word, _ ns: NSString) -> Bool {
        let gap = NSRange(location: NSMaxRange(previous.range), length: next.range.location - NSMaxRange(previous.range))
        guard gap.length == 1, let scalar = Unicode.Scalar(ns.character(at: gap.location)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    /// Runs of letters, digits, apostrophes and hyphens, lowercased with curly apostrophes made straight.
    private static func words(in paragraph: String) -> [Word] {
        var words: [Word] = []
        var start: Int?
        var offset = 0
        func finish() {
            guard let wordStart = start else { return }
            let range = NSRange(location: wordStart, length: offset - wordStart)
            let text = (paragraph as NSString).substring(with: range).lowercased().replacingOccurrences(of: "’", with: "'")
            words.append(Word(text: text, range: range))
            start = nil
        }
        for scalar in paragraph.unicodeScalars {
            if isWordScalar(scalar) {
                if start == nil { start = offset }
            } else {
                finish()
            }
            offset += scalar.utf16.count
        }
        finish()
        return words
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil || "'’-".unicodeScalars.contains(scalar)
    }

    private static let fillers = [
        "just", "really", "very", "basically", "actually", "literally", "quite", "simply", "totally", "truly",
        "definitely", "certainly", "honestly", "seriously", "rather", "somewhat", "pretty much", "kind of",
        "sort of", "a bit", "a little bit", "in fact", "of course", "needless to say", "it goes without saying",
        "for all intents and purposes", "at this point in time", "in order to", "the fact that", "so to speak",
    ]

    private static let cliches = [
        "at the end of the day", "think outside the box", "low-hanging fruit", "move the needle", "game changer",
        "game-changer", "paradigm shift", "touch base", "circle back", "the bottom line", "in a nutshell",
        "best of both worlds", "few and far between", "last but not least", "only time will tell",
        "tip of the iceberg", "easier said than done", "a blessing in disguise", "better late than never",
        "avoid it like the plague", "every cloud has a silver lining", "a silver lining", "par for the course",
        "the elephant in the room", "when all is said and done", "no-brainer", "hit the ground running",
        "push the envelope", "level playing field", "win-win", "it is what it is", "back to the drawing board",
        "in the same boat", "the calm before the storm", "think on your feet", "a perfect storm",
        "time will tell", "read between the lines", "the writing on the wall", "add insult to injury",
    ]

    private static let redundancies = [
        "added bonus", "free gift", "past history", "end result", "each and every", "final outcome",
        "close proximity", "advance planning", "advance warning", "future plans", "basic fundamentals",
        "completely finished", "completely eliminate", "absolutely essential", "unexpected surprise",
        "true fact", "past experience", "join together", "merge together", "repeat again", "revert back",
        "return back", "first and foremost", "various different", "general consensus", "consensus of opinion",
        "new innovation", "brief summary", "sum total", "plan ahead", "postpone until later", "unintended mistake",
        "personal opinion", "exact same", "over exaggerate", "still remains", "ask the question",
        "reason why", "collaborate together", "mutual cooperation",
    ]
}
