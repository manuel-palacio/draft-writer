import Foundation
import NaturalLanguage

public enum LexicalClass: String, CaseIterable, Sendable {
    case noun, verb, adjective, adverb, conjunction

    init?(_ tag: NLTag) {
        switch tag {
        case .noun: self = .noun
        case .verb: self = .verb
        case .adjective: self = .adjective
        case .adverb: self = .adverb
        case .conjunction: self = .conjunction
        default: return nil
        }
    }
}

public struct Highlight: Hashable, Sendable {
    public let range: NSRange
    public let lexicalClass: LexicalClass

    public init(range: NSRange, lexicalClass: LexicalClass) {
        self.range = range
        self.lexicalClass = lexicalClass
    }
}

/// Part-of-speech highlighting with NaturalLanguage's lexical-class tagger, plus style checks on English paragraphs.
/// Works paragraph by paragraph, caches results by paragraph text, and leaves paragraphs in languages without
/// a model uncoloured.
public final class SyntaxHighlighter {
    /// Total paragraph characters the cache may hold before it starts over. A paragraph longer than a tenth
    /// of this is re-tagged each time instead, so one huge paragraph can't fill the cache with its edits.
    private let cacheCharacterLimit: Int
    private var cache: [String: ParagraphAnalysis] = [:]   // paragraph text → its analysis
    private(set) var cachedCharacters = 0
    /// Languages met while tagging that have no lexical-class model installed yet, so a document mixing
    /// languages gets every model it needs (the caller requests them with `NLTagger.requestAssets`).
    public private(set) var missingLanguages: Set<NLLanguage> = []
    private let tagger = NLTagger(tagSchemes: [.lexicalClass])
    private let recognizer = NLLanguageRecognizer()
    private let isSupported: (NLLanguage) -> Bool

    /// `isSupported` says whether a lexical-class model is installed for a language (injectable for tests).
    public init(isSupported: @escaping (NLLanguage) -> Bool = SyntaxHighlighter.hasModel,
                cacheCharacterLimit: Int = 1_000_000) {
        self.isSupported = isSupported
        self.cacheCharacterLimit = cacheCharacterLimit
    }

    public static func hasModel(for language: NLLanguage) -> Bool {
        NLTagger.availableTagSchemes(for: .word, language: language).contains(.lexicalClass)
    }

    /// Highlights for every paragraph touched by `range` (UTF-16, absolute), minus `excluding` (e.g. code).
    public func highlights(in text: String, range: NSRange, excluding: [NSRange]) -> [Highlight] {
        collect(in: text, range: range, excluding: excluding, from: \.highlights) {
            Highlight(range: $1, lexicalClass: $0.lexicalClass)
        }
    }

    /// Style-check matches (fillers, clichés, redundancies) in the English paragraphs touched by `range`,
    /// minus `excluding`. Other languages yield none: the word lists are English.
    public func styleMatches(in text: String, range: NSRange, excluding: [NSRange]) -> [StyleMatch] {
        collect(in: text, range: range, excluding: excluding, from: \.styleMatches) {
            StyleMatch(range: $1, check: $0.check)
        }
    }

    /// What one paragraph yields, with ranges relative to the paragraph.
    private struct ParagraphAnalysis {
        var highlights: [Highlight] = []
        var styleMatches: [StyleMatch] = []
    }

    /// Runs over the paragraphs touched by `range`, moving each item to its absolute range with `relocate`
    /// and dropping the ones that touch `excluding`.
    private func collect<Item: ParagraphRelative>(in text: String, range: NSRange, excluding: [NSRange],
                                                  from items: KeyPath<ParagraphAnalysis, [Item]>,
                                                  relocate: @escaping (Item, NSRange) -> Item) -> [Item] {
        let ns = text as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        let paragraphs = ns.paragraphRange(for: clamped)
        // A long document has thousands of code spans; test each word only against those nearby.
        let excluding = excluding.filter { NSIntersectionRange($0, paragraphs).length > 0 }
        var result: [Item] = []
        ns.enumerateSubstrings(in: paragraphs, options: .byParagraphs) { paragraph, paragraphRange, _, _ in
            guard let paragraph, !paragraph.isEmpty else { return }
            for item in self.analysis(of: paragraph)[keyPath: items] {
                let absolute = NSRange(location: item.range.location + paragraphRange.location, length: item.range.length)
                if !excluding.contains(where: { NSIntersectionRange($0, absolute).length > 0 }) {
                    result.append(relocate(item, absolute))
                }
            }
        }
        return result
    }

    private func analysis(of paragraph: String) -> ParagraphAnalysis {
        if let cached = cache[paragraph] { return cached }
        // nil = no model for this language yet: not cached, so colours appear once the model downloads.
        guard let analysis = analyze(paragraph) else { return ParagraphAnalysis() }
        let size = paragraph.utf16.count
        guard size <= cacheCharacterLimit / 10 else { return analysis }
        if cachedCharacters + size > cacheCharacterLimit {
            cache.removeAll(keepingCapacity: true)
            cachedCharacters = 0
        }
        cache[paragraph] = analysis
        cachedCharacters += size
        return analysis
    }

    private func analyze(_ paragraph: String) -> ParagraphAnalysis? {
        recognizer.reset()
        recognizer.processString(paragraph)
        guard let language = recognizer.dominantLanguage else { return ParagraphAnalysis() }
        guard isSupported(language) else {
            missingLanguages.insert(language)
            return nil
        }
        missingLanguages.remove(language)
        return ParagraphAnalysis(highlights: tag(paragraph, language: language),
                                 styleMatches: language == .english ? StyleChecker.matches(in: paragraph) : [])
    }

    private func tag(_ paragraph: String, language: NLLanguage) -> [Highlight] {
        tagger.string = paragraph
        let whole = paragraph.startIndex..<paragraph.endIndex
        tagger.setLanguage(language, range: whole)
        var highlights: [Highlight] = []
        tagger.enumerateTags(in: whole, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if let tag, let lexicalClass = LexicalClass(tag) {
                highlights.append(Highlight(range: NSRange(range, in: paragraph), lexicalClass: lexicalClass))
            }
            return true
        }
        return highlights
    }
}

/// Something found in a paragraph, at a range relative to it.
private protocol ParagraphRelative {
    var range: NSRange { get }
}

extension Highlight: ParagraphRelative {}
extension StyleMatch: ParagraphRelative {}
