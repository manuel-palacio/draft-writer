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

    /// `text` with every line break (LF, CRLF or CR) written in this style.
    public func apply(to text: String) -> String {
        text.replacing(/\r\n|\r|\n/.matchingSemantics(.unicodeScalar), with: rawValue)
    }
}
