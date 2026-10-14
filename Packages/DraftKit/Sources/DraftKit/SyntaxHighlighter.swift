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

/// Part-of-speech highlighting with NaturalLanguage's lexical-class tagger. Works paragraph by paragraph,
/// caches results by paragraph text, and leaves paragraphs in languages without a model uncoloured.
public final class SyntaxHighlighter {
    static let cacheLimit = 2_000

    private var cache: [String: [Highlight]] = [:]   // paragraph text → highlights relative to the paragraph
    private let tagger = NLTagger(tagSchemes: [.lexicalClass])
    private let recognizer = NLLanguageRecognizer()

    public init() {}

    /// Highlights for every paragraph touched by `range` (UTF-16, absolute), minus `excluding` (e.g. code).
    public func highlights(in text: String, range: NSRange, excluding: [NSRange]) -> [Highlight] {
        let ns = text as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        let paragraphs = ns.paragraphRange(for: clamped)
        var result: [Highlight] = []
        ns.enumerateSubstrings(in: paragraphs, options: .byParagraphs) { paragraph, paragraphRange, _, _ in
            guard let paragraph, !paragraph.isEmpty else { return }
            for h in self.paragraphHighlights(paragraph) {
                let absolute = NSRange(location: h.range.location + paragraphRange.location, length: h.range.length)
                if !excluding.contains(where: { NSIntersectionRange($0, absolute).length > 0 }) {
                    result.append(Highlight(range: absolute, lexicalClass: h.lexicalClass))
                }
            }
        }
        return result
    }

    /// The dominant language of `text` when NaturalLanguage has no lexical-class model for it yet
    /// (the caller may request the model with `NLTagger.requestAssets`).
    public static func needsAssets(_ text: String) -> NLLanguage? {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text) else { return nil }
        return NLTagger.availableTagSchemes(for: .word, language: language).contains(.lexicalClass) ? nil : language
    }

    private func paragraphHighlights(_ paragraph: String) -> [Highlight] {
        if let cached = cache[paragraph] { return cached }
        let highlights = tag(paragraph)
        if cache.count >= Self.cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[paragraph] = highlights
        return highlights
    }

    private func tag(_ paragraph: String) -> [Highlight] {
        recognizer.reset()
        recognizer.processString(paragraph)
        guard let language = recognizer.dominantLanguage,
              NLTagger.availableTagSchemes(for: .word, language: language).contains(.lexicalClass) else { return [] }
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
