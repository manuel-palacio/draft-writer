import Foundation

/// `[[Note]]` links between library notes and `#tag` tokens. Neither is Markdown, so they are found by pattern,
/// outside code and link destinations.
public enum NoteLinks {
    private static let wikilinkPattern = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+)\]\]"#)
    /// A `#` at the start of a word, followed by a name with at least one letter (so `#42` and `&#38;` aren't tags).
    private static let tagPattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_#&/])#([\p{L}\p{N}_-]*\p{L}[\p{L}\p{N}_-]*)"#)

    /// The name of the wikilink at `location` (UTF-16), trimmed; nil if there is none.
    public static func wikilink(in text: String, at location: Int) -> String? {
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        return wikilinkPattern.matches(in: text, range: line)
            .first { NSLocationInRange(location, $0.range) }
            .map { ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The note's tags, lowercased, without the `#`.
    public static func tags(in text: String) -> Set<String> {
        let ns = text as NSString
        return Set(MarkdownStyler.styles(for: text).filter { $0.style == .tag }
            .map { ns.substring(with: $0.range).dropFirst().lowercased() })
    }

    /// Wikilinks (with their brackets greyed) and tags in `text`, except where they overlap `excluding`.
    static func styles(in text: String, excluding: [NSRange]) -> [StyledRange] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        func outside(_ range: NSRange) -> Bool { !excluding.contains { NSIntersectionRange($0, range).length > 0 } }
        var styles: [StyledRange] = []
        for match in wikilinkPattern.matches(in: text, range: whole) where outside(match.range) {
            let r = match.range
            styles.append(StyledRange(range: r, style: .wikilink))
            styles.append(StyledRange(range: NSRange(location: r.location, length: 2), style: .syntaxMarker))
            styles.append(StyledRange(range: NSRange(location: NSMaxRange(r) - 2, length: 2), style: .syntaxMarker))
        }
        for match in tagPattern.matches(in: text, range: whole) where outside(match.range) {
            styles.append(StyledRange(range: match.range, style: .tag))
        }
        return styles
    }
}

extension Library {
    /// The note called `name` (case-insensitive): matched against file names without their extension, or with it
    /// when `name` ends in one the library recognises.
    public static func note(named name: String, in notes: [URL]) -> URL? {
        let hasExtension = fileExtensions.contains((name as NSString).pathExtension.lowercased())
        return notes.first { url in
            let candidate = hasExtension ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            return candidate.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    /// Creates an empty `<name>.md` in `folder`; never overwrites.
    public static func createNote(named name: String, in folder: URL) throws -> URL {
        let trimmed = try validatedName(name)
        let url = folder.appending(path: fileExtensions.contains((trimmed as NSString).pathExtension.lowercased()) ? trimmed : "\(trimmed).md")
        try Data().write(to: url, options: .withoutOverwriting)
        return url
    }
}
