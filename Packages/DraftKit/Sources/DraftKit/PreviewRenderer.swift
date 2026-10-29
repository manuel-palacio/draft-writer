import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Renders Markdown to HTML with cmark-gfm (GitHub Flavored Markdown). Text is escaped, raw HTML is
/// omitted (cmark's safe default), and block elements carry `data-sourcepos` for scroll sync.
public enum PreviewRenderer {
    private static let extensionNames = ["table", "strikethrough", "autolink", "tasklist"]
    private static let options = CMARK_OPT_SOURCEPOS

    /// With a `folder`, `/path` content blocks embed files from it (see `ContentBlocks`).
    public static func body(for markdown: String, folder: DocumentFolder? = nil) -> String {
        let html = render(markdown)
        guard let folder else { return html }
        return ContentBlocks.expand(html, in: folder)
    }

    static func render(_ markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        // Feed by byte count, not strlen: an embedded NUL must not cut the document short.
        var markdown = markdown
        markdown.withUTF8 { bytes in
            bytes.withMemoryRebound(to: CChar.self) { chars in
                if let base = chars.baseAddress { cmark_parser_feed(parser, base, chars.count) }
            }
        }
        guard let root = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(root) }
        guard let html = cmark_render_html(root, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }
        return String(cString: html)
    }

    public static func page(for markdown: String, title: String, css: String, folder: DocumentFolder? = nil) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>\(css)</style>
        </head><body><article id="content">\(body(for: markdown, folder: folder))</article></body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
