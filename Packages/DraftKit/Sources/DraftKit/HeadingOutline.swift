import Foundation
import Markdown

/// One heading in a document, for Jump to Heading.
public struct OutlineHeading: Hashable, Sendable {
    public let level: Int
    /// The heading's text without Markdown syntax.
    public let title: String
    /// UTF-16 offset of the heading's first character (its `#`, or a setext heading's text).
    public let location: Int
}

/// The document's H1–H6 headings, ATX and setext, in order. Parsed with swift-markdown,
/// so `#` lines inside code blocks are not headings.
public enum HeadingOutline {
    public static func headings(in text: String) -> [OutlineHeading] {
        var text = text
        text.makeContiguousUTF8()   // fast UTF-8 -> UTF-16 conversion, as in MarkdownStyler
        var collector = HeadingCollector(converter: SourceRangeConverter(text))
        collector.visit(Document(parsing: text))
        return collector.headings
    }
}

private struct HeadingCollector: MarkupWalker {
    let converter: SourceRangeConverter
    var headings: [OutlineHeading] = []

    mutating func visitHeading(_ heading: Heading) {
        guard let range = heading.range, let r = converter.nsRange(range) else { return }
        headings.append(OutlineHeading(level: heading.level, title: heading.plainText, location: r.location))
    }
}
