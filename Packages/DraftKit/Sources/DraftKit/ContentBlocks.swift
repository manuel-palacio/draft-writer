import Foundation
import UniformTypeIdentifiers

/// iA Writer content blocks: a paragraph that is exactly `/path` (relative to the document folder) is
/// replaced by that file, Markdown and text rendered, images shown. Expansion works on cmark's HTML
/// rather than the source, so the `data-sourcepos` of everything around a block stays true for scroll sync.
/// Missing, unsupported, cyclic or too deeply nested blocks are left as written.
enum ContentBlocks {
    static let maxDepth = 8
    /// `.txt` is rendered as Markdown too: plain prose renders the same, and many Markdown files use `.txt`.
    private static let textExtensions: Set = ["md", "markdown", "txt"]

    /// Only a paragraph holding plain text (no markup, no line break) can be a block.
    private static var blockParagraph: Regex<(Substring, Substring, Substring)> {
        #/<p data-sourcepos="([^"]+)">(/[^<\n]+)</p>/#
    }
    private static var sourcepos: Regex<Substring> { #/ data-sourcepos="[^"]*"/# }

    /// `chain` is the files already being embedded, outermost first.
    static func expand(_ html: String, in folder: DocumentFolder, chain: [String] = []) -> String {
        html.replacing(blockParagraph) { match in
            let path = unescape(String(match.2)).trimmingCharacters(in: .whitespaces)
            return embed(path: path, sourcepos: String(match.1), in: folder, chain: chain) ?? String(match.0)
        }
    }

    private static func embed(path: String, sourcepos: String, in folder: DocumentFolder, chain: [String]) -> String? {
        guard !path.hasPrefix("//") else { return nil }
        let relativePath = String(path.dropFirst())
        let ext = (relativePath as NSString).pathExtension.lowercased()
        if textExtensions.contains(ext) {
            return embedText(relativePath, sourcepos: sourcepos, in: folder, chain: chain)
        }
        if UTType(filenameExtension: ext)?.conforms(to: .image) == true, folder.fileExists(relativePath: relativePath) {
            return embedImage(relativePath, sourcepos: sourcepos)
        }
        return nil
    }

    private static func embedText(_ relativePath: String, sourcepos: String, in folder: DocumentFolder,
                                  chain: [String]) -> String? {
        let key = (relativePath as NSString).standardizingPath
        guard chain.count < maxDepth, !chain.contains(key), let text = folder.text(relativePath: relativePath) else {
            return nil
        }
        let inner = expand(PreviewRenderer.render(text), in: folder, chain: chain + [key])
        // Only the block itself maps to the source; positions inside another file would mislead scroll sync.
        return #"<div class="content-block" data-sourcepos="\#(sourcepos)">\#(inner.replacing(Self.sourcepos, with: ""))</div>"#
    }

    /// The page's base URL is the document folder, so a relative `src` loads like any Markdown image.
    private static func embedImage(_ relativePath: String, sourcepos: String) -> String {
        let src = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
        let escape = PreviewRenderer.escape
        return #"<p class="content-block" data-sourcepos="\#(sourcepos)"><img src="\#(escape(src))" alt="\#(escape(relativePath))"></p>"#
    }

    /// Undoes cmark's text escaping.
    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
