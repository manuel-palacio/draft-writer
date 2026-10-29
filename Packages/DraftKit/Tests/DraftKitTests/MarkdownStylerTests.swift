import Foundation
import Testing
@testable import DraftKit

@Suite struct MarkdownStylerTests {
    /// (substring, style) pairs for every styled range, so assertions read like the Markdown.
    func pairs(_ text: String) -> [(String, MarkdownStyle)] {
        MarkdownStyler.styles(for: text).map { ((text as NSString).substring(with: $0.range), $0.style) }
    }

    func contains(_ text: String, _ substring: String, _ style: MarkdownStyle) -> Bool {
        pairs(text).contains { $0.0 == substring && $0.1 == style }
    }

    @Test func heading() {
        #expect(contains("## Title", "## Title", .heading(level: 2)))
        #expect(contains("## Title", "##", .syntaxMarker))
    }

    @Test func emphasisAndStrong() {
        let text = "a *b* **c**"
        #expect(contains(text, "*b*", .emphasis))
        #expect(contains(text, "**c**", .strong))
        #expect(pairs(text).filter { $0.0 == "*" && $0.1 == .syntaxMarker }.count == 2)
        #expect(pairs(text).filter { $0.0 == "**" && $0.1 == .syntaxMarker }.count == 2)
    }

    @Test func inlineCode() {
        #expect(contains("x `y` z", "`y`", .inlineCode))
    }

    @Test func fencedCode() {
        let text = "```\nlet *a* = 1\n```"
        #expect(contains(text, text, .codeBlock))
        #expect(!pairs(text).contains { $0.1 == .emphasis })
    }

    @Test func link() {
        let text = "[Draft](https://x.io)"
        #expect(contains(text, text, .link))
        #expect(contains(text, "https://x.io", .linkDestination))
    }

    @Test func listAndQuote() {
        let text = "- item\n\n> quote"
        #expect(contains(text, "-", .listMarker))
        #expect(contains(text, "> quote", .blockQuote))
    }

    @Test func stylesAfterEmojiAndSwedish() {
        #expect(contains("👋 åäö *ord*", "*ord*", .emphasis))
    }

    @Test func emptyText() {
        #expect(MarkdownStyler.styles(for: "").isEmpty)
    }

    @Test func crlf() {
        #expect(contains("# A\r\n*b*", "*b*", .emphasis))
    }

    @Test func setextHeadingStopsAtItsUnderline() {
        let text = "Title\n=====\n*x*"
        #expect(contains(text, "Title\n=====", .heading(level: 1)))
        #expect(!pairs(text).contains { $0.1 == .heading(level: 1) && $0.0.contains("*x*") })
    }

    @Test func setextHeadingAtEndOfDocument() {
        #expect(contains("Title\n---", "Title\n---", .heading(level: 2)))
    }

    @Test func everyQuoteMarkerIsGreyed() {
        let text = "> one\n> two\n>three"
        let markers = MarkdownStyler.styles(for: text).filter { $0.style == .syntaxMarker }.map(\.range.location)
        #expect(markers == [0, 6, 12])
    }

    func markers(_ text: String) -> [String] {
        pairs(text).filter { $0.1 == .syntaxMarker }.map(\.0)
    }

    @Test func strikethrough() {
        let text = "a ~~gone~~ b"
        #expect(contains(text, "~~gone~~", .strikethrough))
        #expect(markers(text) == ["~~", "~~"])
    }

    @Test func image() {
        let text = "![alt](img/a.png)"
        #expect(contains(text, "!", .syntaxMarker))
        #expect(contains(text, "img/a.png", .linkDestination))
        #expect(!pairs(text).contains { $0.1 == .link })   // not underlined like a link
    }

    @Test func thematicBreaks() {
        #expect(contains("a\n\n---\n\nb", "---", .syntaxMarker))
        #expect(contains("a\n\n***\n\nb", "***", .syntaxMarker))
        #expect(!pairs("a\n\n***\n\nb").contains { $0.1 == .strong })
    }

    @Test func tablePipesAndDelimiterRow() {
        let text = "| A | B |\n|---|:-:|\n| 1 | `x\\|y` |"
        let ns = text as NSString
        let greyed = MarkdownStyler.styles(for: text).filter { $0.style == .syntaxMarker }.map(\.range)
        #expect(greyed.contains(ns.range(of: "|---|:-:|")))
        let pipes = greyed.filter { $0.length == 1 }.map { ns.substring(with: $0) }
        #expect(pipes == Array(repeating: "|", count: 6))   // the escaped pipe in code is content
    }

    @Test func nestedQuoteMarkersAreGreyed() {
        let text = "> > deep"
        let markers = MarkdownStyler.styles(for: text).filter { $0.style == .syntaxMarker }.map(\.range.location)
        #expect(Set(markers) == [0, 2])
    }
}
