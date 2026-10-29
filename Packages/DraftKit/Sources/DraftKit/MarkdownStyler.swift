import Foundation
import Markdown

public enum MarkdownStyle: Hashable, Sendable {
    case heading(level: Int)
    case emphasis, strong, strikethrough, inlineCode, codeBlock
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

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        if let r = emit(strikethrough, .strikethrough) { markEnds(r, width: leadingRun(of: "~", in: r)) }
        descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        emit(inlineCode, .inlineCode)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        emit(codeBlock, .codeBlock)
    }

    mutating func visitLink(_ link: Link) {
        if let r = emit(link, .link), let destination = destination(in: r) {
            add(destination, .linkDestination)
        }
        descendInto(link)
    }

    /// Greyed like a link's markup, but not underlined: the image isn't clickable in the editor.
    mutating func visitImage(_ image: Image) {
        if let range = image.range, let r = converter.nsRange(range) {
            add(NSRange(location: r.location, length: 1), .syntaxMarker)
            if let destination = destination(in: r) { add(destination, .linkDestination) }
        }
        descendInto(image)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        // swift-markdown's range runs to the start of the next line; grey only the break's own line.
        guard let range = thematicBreak.range, let r = converter.nsRange(range) else { return }
        var contentsEnd = 0
        ns.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: r.location, length: 0))
        add(NSRange(location: r.location, length: contentsEnd - r.location), .syntaxMarker)
    }

    /// Greys the delimiter row and every unescaped `|` (GFM requires pipes inside cells, even in code, to be escaped).
    mutating func visitTable(_ table: Table) {
        if let range = table.range, let r = converter.nsRange(range) {
            var lineStart = r.location
            var row = 0
            while lineStart < NSMaxRange(r) {
                var lineEnd = 0, next = 0
                ns.getLineStart(nil, end: &next, contentsEnd: &lineEnd, for: NSRange(location: lineStart, length: 0))
                let line = NSRange(location: lineStart, length: min(lineEnd, NSMaxRange(r)) - lineStart)
                if row == 1 { add(line, .syntaxMarker) } else { markPipes(in: line) }
                lineStart = next
                row += 1
            }
        }
        descendInto(table)
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

    /// The destination inside a link or image's `[text](destination)` source, without the parentheses.
    private func destination(in r: NSRange) -> NSRange? {
        let source = ns.substring(with: r) as NSString
        let open = source.range(of: "](")
        guard open.location != NSNotFound, source.hasSuffix(")") else { return nil }
        let start = open.location + open.length
        return NSRange(location: r.location + start, length: r.length - start - 1)
    }

    private mutating func markPipes(in line: NSRange) {
        let pipe = UInt16(UInt8(ascii: "|")), backslash = UInt16(UInt8(ascii: "\\"))
        for i in line.location..<NSMaxRange(line) where ns.character(at: i) == pipe {
            if i == line.location || ns.character(at: i - 1) != backslash {
                add(NSRange(location: i, length: 1), .syntaxMarker)
            }
        }
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
