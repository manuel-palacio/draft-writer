import Foundation

/// A file's line-break style. Detected when a file opens and re-applied when it saves, so a CRLF file
/// stays CRLF even though newlines typed in the editor are bare LF.
public enum LineEnding: String, Sendable {
    case lf = "\n", crlf = "\r\n", cr = "\r"

    /// The style of the first line break (LF when there is none), as most editors do.
    public static func detect(in text: String) -> LineEnding {
        let scalars = text.unicodeScalars
        guard let index = scalars.firstIndex(where: { $0 == "\n" || $0 == "\r" }) else { return .lf }
        if scalars[index] == "\n" { return .lf }
        let next = scalars.index(after: index)
        return next < scalars.endIndex && scalars[next] == "\n" ? .crlf : .cr
    }

    /// `text` with every line break (LF, CRLF or CR) written in this style. Uses NSString's literal
    /// replacement, which is ~25× faster than Swift Regex on large text; this runs on every save.
    public func apply(to text: String) -> String {
        let hasCR = (text as NSString).range(of: "\r", options: .literal).location != NSNotFound
        if self == .lf && !hasCR { return text }   // the common case: nothing to change
        let result = NSMutableString(string: text)
        let all = { NSRange(location: 0, length: result.length) }
        if hasCR {
            result.replaceOccurrences(of: "\r\n", with: "\n", options: .literal, range: all())
            result.replaceOccurrences(of: "\r", with: "\n", options: .literal, range: all())
        }
        if self != .lf {
            result.replaceOccurrences(of: "\n", with: rawValue, options: .literal, range: all())
        }
        return result as String
    }
}
