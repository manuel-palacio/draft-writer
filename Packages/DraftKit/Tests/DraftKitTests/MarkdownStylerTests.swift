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
}
