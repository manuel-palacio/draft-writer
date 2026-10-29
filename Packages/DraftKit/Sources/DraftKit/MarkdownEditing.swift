import Foundation
import Markdown

/// One replacement in the text and the selection after it (UTF-16 ranges). The editor applies it as a single
/// undo step.
public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

/// Markdown-aware editing commands: emphasis and link wrapping, list continuation, list indentation and task
/// toggling. Each returns the edit to make, or nil when the command doesn't apply (the editor then does the
/// plain thing, e.g. inserts a newline or a tab).
public enum MarkdownEditing {
    public static let indentUnit = "    "

    public static func wrap(_ text: String, selection: NSRange, marker: String) -> TextEdit {
        let inner = (text as NSString).substring(with: selection)
        let width = (marker as NSString).length
        return TextEdit(range: selection, replacement: marker + inner + marker,
                        selection: NSRange(location: selection.location + width, length: selection.length))
    }

    /// `[selection]()` with the caret in the parentheses, or `[]()` with the caret in the brackets.
    public static func link(_ text: String, selection: NSRange) -> TextEdit {
        let inner = (text as NSString).substring(with: selection)
        let caret = selection.length == 0 ? selection.location + 1 : NSMaxRange(selection) + 3
        return TextEdit(range: selection, replacement: "[\(inner)]()", selection: NSRange(location: caret, length: 0))
    }

    /// Return in a list item, quote or task continues it (renumbering the ordered items below); Return on an
    /// empty item removes its marker, ending the list.
    public static func newline(_ text: String, at caret: Int) -> TextEdit? {
        let ns = text as NSString
        let line = contentsRange(ofLineAt: caret, in: ns)
        guard let item = ListPrefix(ns.substring(with: line)), caret >= line.location + item.prefixLength else { return nil }
        if item.isEmpty {
            return TextEdit(range: line, replacement: "", selection: NSRange(location: line.location, length: 0))
        }
        let renumbered = item.number.map { renumberedLines(after: line, in: ns, indent: item.indent, from: $0 + 2) } ?? []
        let end = renumbered.last.map { NSMaxRange($0.line) } ?? caret
        let tail = NSMutableString(string: ns.substring(with: NSRange(location: caret, length: end - caret)))
        for change in renumbered.reversed() {
            tail.replaceCharacters(in: NSRange(location: change.digits.location - caret, length: change.digits.length),
                                   with: change.number)
        }
        let prefix = "\n" + item.continuation
        return TextEdit(range: NSRange(location: caret, length: end - caret), replacement: prefix + (tail as String),
                        selection: NSRange(location: caret + (prefix as NSString).length, length: 0))
    }

    /// Tab on list items: indents every list line in the selection.
    public static func indent(_ text: String, selection: NSRange) -> TextEdit? {
        transformLines(text, selection: selection) { line, item in
            item == nil || item!.isQuote ? nil : indentUnit + line
        }
    }

    /// Shift-Tab on list items: removes one level (a tab or up to four spaces) from every list line in the selection.
    public static func outdent(_ text: String, selection: NSRange) -> TextEdit? {
        transformLines(text, selection: selection) { line, item in
            guard let item, !item.isQuote, !item.indent.isEmpty else { return nil }
            let removed = item.indent.hasPrefix("\t") ? 1 : item.indent.prefix(indentUnit.count).prefix { $0 == " " }.count
            return String(line.dropFirst(removed))
        }
    }

    /// Switches `[ ]` and `[x]` on every task line in the selection.
    public static func toggleTask(_ text: String, selection: NSRange) -> TextEdit? {
        transformLines(text, selection: selection) { line, item in
            guard let box = item?.checkbox else { return nil }
            let mark = NSRange(location: box.location + 1, length: 1)
            let checked = (line as NSString).substring(with: mark) != " "
            return (line as NSString).replacingCharacters(in: mark, with: checked ? " " : "x")
        }
    }

    /// The destination of the Markdown link or autolink at `location` (UTF-16), if any.
    public static func linkDestination(in text: String, at location: Int) -> String? {
        let ns = text as NSString
        guard location < ns.length else { return nil }
        var paragraph = ns.substring(with: ns.paragraphRange(for: NSRange(location: location, length: 0)))
        paragraph.makeContiguousUTF8()
        let offset = location - ns.paragraphRange(for: NSRange(location: location, length: 0)).location
        var finder = LinkFinder(text: paragraph, offset: offset)
        finder.visit(Document(parsing: paragraph))
        return finder.destination ?? bareURL(in: paragraph, at: offset)
    }

    /// swift-markdown doesn't autolink bare URLs (GFM's extended autolinks), so find those as the preview shows them.
    private static func bareURL(in paragraph: String, at offset: Int) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: (paragraph as NSString).length)
        return detector?.matches(in: paragraph, range: range)
            .first { NSLocationInRange(offset, $0.range) }
            .map { (paragraph as NSString).substring(with: $0.range) }
    }

    // MARK: Lines

    private static func contentsRange(ofLineAt location: Int, in ns: NSString) -> NSRange {
        var start = 0, contentsEnd = 0
        ns.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: min(location, ns.length), length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    /// The ordered items after `line` at the same indentation, up to the first blank line or shallower line, with
    /// the numbers they get. Deeper lines (nested content) are passed over.
    private static func renumberedLines(after line: NSRange, in ns: NSString, indent: String, from first: Int)
        -> [(line: NSRange, digits: NSRange, number: String)] {
        var changes: [(line: NSRange, digits: NSRange, number: String)] = []
        var next = NSMaxRange(ns.lineRange(for: line))
        while next < ns.length {
            let current = contentsRange(ofLineAt: next, in: ns)
            let string = ns.substring(with: current)
            next = NSMaxRange(ns.lineRange(for: current))
            guard !string.allSatisfy(\.isWhitespace) else { break }
            let lineIndent = string.prefix { $0 == " " || $0 == "\t" }
            if lineIndent.count > indent.count { continue }
            guard lineIndent.count == indent.count, let item = ListPrefix(string), let digits = item.digits else { break }
            let number = String(first + changes.count)
            changes.append((current, NSRange(location: current.location + digits.location, length: digits.length), number))
        }
        return changes
    }

    /// Applies `transform` (line, its list item) to every line touched by `selection`; nil if no line changed.
    private static func transformLines(_ text: String, selection: NSRange,
                                       transform: (String, ListPrefix?) -> String?) -> TextEdit? {
        let ns = text as NSString
        let block = ns.lineRange(for: selection)
        var replacement = ""
        var changed = false
        var selectionStart = selection.location, selectionEnd = NSMaxRange(selection)
        var shift = 0
        var lineStart = block.location
        while lineStart < NSMaxRange(block) || (lineStart == block.location && block.length == 0) {
            let contents = contentsRange(ofLineAt: lineStart, in: ns)
            let full = ns.lineRange(for: contents)
            let line = ns.substring(with: contents)
            let newLine = transform(line, ListPrefix(line)) ?? line
            changed = changed || newLine != line
            let delta = (newLine as NSString).length - contents.length
            // A position belongs to the line it's on; the end of the last line (no line break) belongs to it too.
            func owns(_ position: Int) -> Bool {
                position >= contents.location && (position < NSMaxRange(full) || NSMaxRange(contents) == NSMaxRange(full))
            }
            if owns(selection.location) { selectionStart = moved(selection.location, lineStart: contents.location, shift: shift, delta: delta) }
            if owns(NSMaxRange(selection)) { selectionEnd = moved(NSMaxRange(selection), lineStart: contents.location, shift: shift, delta: delta) }
            replacement += newLine + ns.substring(with: NSRange(location: NSMaxRange(contents), length: NSMaxRange(full) - NSMaxRange(contents)))
            shift += delta
            if full.length == 0 { break }
            lineStart = NSMaxRange(full)
        }
        guard changed else { return nil }
        return TextEdit(range: block, replacement: replacement,
                        selection: NSRange(location: selectionStart, length: max(0, selectionEnd - selectionStart)))
    }

    /// Where `position` lands once its line (starting at `lineStart`) grew by `delta` at its start, after earlier
    /// lines grew by `shift`. Text removed from the start pulls the position back, but not past the line start.
    private static func moved(_ position: Int, lineStart: Int, shift: Int, delta: Int) -> Int {
        position + shift + (delta >= 0 ? delta : max(delta, lineStart - position))
    }
}

/// The Markdown prefix of a list item, quote or task line: `  - [ ] `, `3. `, `> `.
struct ListPrefix {
    private static let listPattern = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\](?:[ \t]+|$))?"#)
    private static let quotePattern = try! NSRegularExpression(pattern: #"^([ \t]*)((?:>[ \t]?)+)"#)

    let indent: String
    /// Everything that starts the next item: indentation, marker (numbered one higher), spacing, empty checkbox.
    let continuation: String
    let prefixLength: Int
    let number: Int?
    /// The number's digits, relative to the line.
    let digits: NSRange?
    /// The `[ ]`, relative to the line.
    let checkbox: NSRange?
    let isQuote: Bool
    let isEmpty: Bool

    init?(_ line: String) {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func group(_ match: NSTextCheckingResult, _ i: Int) -> String? {
            match.range(at: i).location == NSNotFound ? nil : ns.substring(with: match.range(at: i))
        }
        if let match = Self.listPattern.firstMatch(in: line, range: whole) {
            indent = group(match, 1)!
            let spacing = group(match, 5)!
            number = group(match, 3).flatMap { Int($0) }
            digits = number == nil ? nil : match.range(at: 3)
            let marker = number.map { "\($0 + 1)\(group(match, 4)!)" } ?? group(match, 2)!
            checkbox = match.range(at: 6).location == NSNotFound ? nil : NSRange(location: match.range(at: 6).location, length: 3)
            continuation = indent + marker + spacing + (checkbox == nil ? "" : "[ ] ")
            prefixLength = match.range.length
            isQuote = false
        } else if let match = Self.quotePattern.firstMatch(in: line, range: whole) {
            indent = group(match, 1)!
            number = nil
            digits = nil
            checkbox = nil
            continuation = indent + group(match, 2)!
            prefixLength = match.range.length
            isQuote = true
        } else {
            return nil
        }
        isEmpty = ns.substring(from: prefixLength).allSatisfy(\.isWhitespace)
    }
}

private struct LinkFinder: MarkupWalker {
    let converter: SourceRangeConverter
    let offset: Int
    var destination: String?

    init(text: String, offset: Int) {
        converter = SourceRangeConverter(text)
        self.offset = offset
    }

    mutating func visitLink(_ link: Link) {
        if let range = link.range, let r = converter.nsRange(range), NSLocationInRange(offset, r) {
            destination = link.destination
        }
        descendInto(link)
    }
}
