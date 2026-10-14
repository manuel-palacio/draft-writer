import Foundation
import NaturalLanguage

public enum FocusMode: String, CaseIterable, Sendable {
    case off, sentence, paragraph

    public var next: FocusMode {
        switch self {
        case .off: .sentence
        case .sentence: .paragraph
        case .paragraph: .off
        }
    }
}

/// Finds the range focus mode keeps bright: the sentence or paragraph around the selection.
/// All ranges are UTF-16 (`NSString`) ranges.
public enum FocusController {
    public static func brightRange(in text: String, selection: NSRange, mode: FocusMode) -> NSRange? {
        guard mode != .off else { return nil }
        let ns = text as NSString
        let start = min(selection.location, ns.length)
        let end = min(NSMaxRange(selection), ns.length)
        let paragraph = trimmingTrailing(ns.paragraphRange(for: NSRange(location: start, length: end - start)), in: ns)
        guard mode == .sentence, paragraph.length > 0 else { return paragraph }

        let sentences = sentenceRanges(in: paragraph, of: text)
        let touched = sentences.filter { r in
            end > start
                ? r.location < end && NSMaxRange(r) > start
                : r.location <= start && start < NSMaxRange(r)
        }
        guard let first = touched.first ?? sentences.last, let last = touched.last ?? sentences.last else {
            return paragraph
        }
        return trimmingTrailing(NSUnionRange(first, last), in: ns)
    }

    private static func sentenceRanges(in paragraph: NSRange, of text: String) -> [NSRange] {
        guard let range = Range(paragraph, in: text) else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: range).map { NSRange($0, in: text) }
    }

    private static func trimmingTrailing(_ range: NSRange, in ns: NSString) -> NSRange {
        var length = range.length
        while length > 0,
              let scalar = Unicode.Scalar(ns.character(at: range.location + length - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }
}
