import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Renders Markdown to HTML with cmark-gfm (GitHub Flavored Markdown). Text is escaped, raw HTML is
/// omitted (cmark's safe default), and block elements carry `data-sourcepos` for scroll sync.
public enum PreviewRenderer {
    private static let extensionNames = ["table", "strikethrough", "autolink", "tasklist"]
    private static let options = CMARK_OPT_SOURCEPOS

    public static func body(for markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        markdown.withCString { cmark_parser_feed(parser, $0, strlen($0)) }
        guard let root = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(root) }
        guard let html = cmark_render_html(root, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }
        return String(cString: html)
    }

    public static func page(for markdown: String, title: String, css: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>\(css)</style>
        </head><body><article id="content">\(body(for: markdown))</article></body></html>
        """
    }

    /// 1-based source line containing the UTF-16 `offset` (CR, LF and CRLF end lines, as in CommonMark).
    public static func line(atUTF16Offset offset: Int, in text: String) -> Int {
        var line = 1
        var previous: UInt16 = 0
        for (index, unit) in text.utf16.enumerated() {
            if index >= offset { break }
            if unit == 0x0A, previous != 0x0D { line += 1 }
            if unit == 0x0D { line += 1 }
            previous = unit
        }
        return line
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
