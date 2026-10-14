import Foundation
import Markdown

/// Maps swift-markdown source ranges (1-based line + 1-based UTF-8 byte column) to
/// UTF-16 `NSRange`s, which is what AppKit expects.
struct SourceRangeConverter {
    private let text: String
    /// UTF-8 offset of the first byte of each line. Lines end at `\n`, `\r\n` or `\r`, as in CommonMark.
    private let lineStarts: [Int]

    init(_ text: String) {
        self.text = text
        var starts = [0]
        let bytes = Array(text.utf8)
        var i = 0
        while i < bytes.count {
            if bytes[i] == UInt8(ascii: "\r") {
                if i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "\n") { i += 1 }
                starts.append(i + 1)
            } else if bytes[i] == UInt8(ascii: "\n") {
                starts.append(i + 1)
            }
            i += 1
        }
        lineStarts = starts
    }

    func nsRange(_ range: SourceRange) -> NSRange? {
        guard let lower = index(range.lowerBound), let upper = index(range.upperBound), lower <= upper else {
            return nil
        }
        return NSRange(lower..<upper, in: text)
    }

    private func index(_ location: SourceLocation) -> String.Index? {
        guard location.line >= 1, location.line <= lineStarts.count else { return nil }
        let offset = lineStarts[location.line - 1] + location.column - 1
        guard offset >= 0, offset <= text.utf8.count else { return nil }
        return text.utf8.index(text.utf8.startIndex, offsetBy: offset)
    }
}
