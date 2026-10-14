import Foundation
import Markdown

public enum MarkdownStyle: Hashable, Sendable {
    case heading(level: Int)
    case emphasis, strong, inlineCode, codeBlock
    case link, linkDestination
    case blockQuote, listMarker, syntaxMarker
}

public struct StyledRange: Hashable, Sendable {
    public let range: NSRange
    public let style: MarkdownStyle

    public init(range: NSRange, style: MarkdownStyle) {
        self.range = range
        self.style = style
    }
}

/// Parses Markdown with swift-markdown and reports which UTF-16 ranges get which display style.
/// Never changes the text; the editor turns these into display attributes.
public enum MarkdownStyler {
    public static func styles(for text: String) -> [StyledRange] {
        var walker = StyleWalker(text: text)
        walker.visit(Document(parsing: text))
        return walker.styles
    }
}

private struct StyleWalker: MarkupWalker {
    let ns: NSString
    let converter: SourceRangeConverter
    var styles: [StyledRange] = []

    init(text: String) {
        ns = text as NSString
        converter = SourceRangeConverter(text)
    }

    mutating func visitHeading(_ heading: Heading) {
        if let r = emit(heading, .heading(level: heading.level)) {
            let hashes = leadingRun(of: "#", in: r)
            if hashes > 0 { add(NSRange(location: r.location, length: hashes), .syntaxMarker) }
        }
        descendInto(heading)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let r = emit(emphasis, .emphasis) { markEnds(r, width: 1) }
        descendInto(emphasis)
    }

    mutating func visitStrong(_ strong: Strong) {
        if let r = emit(strong, .strong) { markEnds(r, width: 2) }
        descendInto(strong)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        emit(inlineCode, .inlineCode)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        emit(codeBlock, .codeBlock)
    }

    mutating func visitLink(_ link: Link) {
        if let r = emit(link, .link) {
            let source = ns.substring(with: r) as NSString
            let open = source.range(of: "](")
            if open.location != NSNotFound, source.hasSuffix(")") {
                let start = open.location + open.length
                let destination = NSRange(location: r.location + start, length: r.length - start - 1)
                add(destination, .linkDestination)
            }
        }
        descendInto(link)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        if let r = emit(blockQuote, .blockQuote), r.length > 0, ns.character(at: r.location) == UInt16(UInt8(ascii: ">")) {
            add(NSRange(location: r.location, length: 1), .syntaxMarker)
        }
        descendInto(blockQuote)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let range = listItem.range, let r = converter.nsRange(range) {
            let line = ns.substring(with: r) as NSString
            let marker = line.rangeOfCharacter(from: .whitespacesAndNewlines)
            let length = marker.location == NSNotFound ? line.length : marker.location
            if length > 0 { add(NSRange(location: r.location, length: length), .listMarker) }
        }
        descendInto(listItem)
    }

    @discardableResult
    private mutating func emit(_ markup: Markup, _ style: MarkdownStyle) -> NSRange? {
        guard let range = markup.range, let r = converter.nsRange(range) else { return nil }
        add(r, style)
        return r
    }

    private mutating func add(_ range: NSRange, _ style: MarkdownStyle) {
        styles.append(StyledRange(range: range, style: style))
    }

    private mutating func markEnds(_ r: NSRange, width: Int) {
        guard r.length >= 2 * width else { return }
        add(NSRange(location: r.location, length: width), .syntaxMarker)
        add(NSRange(location: NSMaxRange(r) - width, length: width), .syntaxMarker)
    }

    private func leadingRun(of character: Character, in r: NSRange) -> Int {
        let unit = character.utf16.first!
        var n = 0
        while n < r.length, ns.character(at: r.location + n) == unit { n += 1 }
        return n
    }
}
