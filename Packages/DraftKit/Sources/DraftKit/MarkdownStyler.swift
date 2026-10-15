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
        // Text from NSTextView is a bridged UTF-16 string, where UTF-8 offsets are O(n); a native copy
        // makes the UTF-8 -> UTF-16 range conversion fast (9 s -> ~20 ms on 50,000 words).
        var text = text
        text.makeContiguousUTF8()
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
        if let range = heading.range, var r = converter.nsRange(range) {
            let hashes = leadingRun(of: "#", in: r)
            if hashes > 0 {
                add(NSRange(location: r.location, length: hashes), .syntaxMarker)
            } else if let underlineEnd = setextUnderlineEnd(heading) {
                // swift-markdown can extend a setext heading's range into the next block; stop at the underline.
                r.length = min(r.length, underlineEnd - r.location)
            }
            add(r, .heading(level: heading.level))
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
        if let r = emit(blockQuote, .blockQuote) {
            // Grey the `>` on every line, found at the quote's own column so nested quotes mark their own.
            let column = r.location - ns.lineRange(for: NSRange(location: r.location, length: 0)).location
            var lineStart = r.location - column
            while lineStart < NSMaxRange(r) {
                var lineEnd = 0, next = 0
                ns.getLineStart(nil, end: &next, contentsEnd: &lineEnd, for: NSRange(location: lineStart, length: 0))
                var i = lineStart + column
                while i < lineEnd, i - lineStart - column < 4, ns.character(at: i) == 0x20 { i += 1 }
                if i < lineEnd, ns.character(at: i) == UInt16(UInt8(ascii: ">")) {
                    add(NSRange(location: i, length: 1), .syntaxMarker)
                }
                lineStart = next
            }
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

    /// UTF-16 offset just past a setext heading's underline (excluding the line break), or nil.
    private func setextUnderlineEnd(_ heading: Heading) -> Int? {
        guard let last = heading.children.reversed().first(where: { $0.range != nil })?.range,
              let content = converter.nsRange(last) else { return nil }
        let contentLine = ns.lineRange(for: NSRange(location: NSMaxRange(content), length: 0))
        guard NSMaxRange(contentLine) < ns.length || contentLine.length > 0 else { return nil }
        var end = 0
        ns.getLineStart(nil, end: nil, contentsEnd: &end, for: NSRange(location: NSMaxRange(contentLine), length: 0))
        return end
    }

    private func leadingRun(of character: Character, in r: NSRange) -> Int {
        let unit = character.utf16.first!
        var n = 0
        while n < r.length, ns.character(at: r.location + n) == unit { n += 1 }
        return n
    }
}
