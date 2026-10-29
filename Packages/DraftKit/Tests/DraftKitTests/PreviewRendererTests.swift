import Foundation
import Testing
@testable import DraftKit

@Suite struct PreviewRendererTests {
    @Test func heading() {
        #expect(PreviewRenderer.body(for: "# Hi *there*").contains(#"<h1 data-sourcepos="1:1-1:12">Hi <em>there</em></h1>"#))
    }

    @Test func escapesAngleBrackets() {
        #expect(PreviewRenderer.body(for: "a < b & c").contains("a &lt; b &amp; c"))
    }

    @Test func omitsRawScript() {
        #expect(!PreviewRenderer.body(for: "<script>alert(1)</script>").contains("<script>"))
    }

    @Test func table() {
        let html = PreviewRenderer.body(for: "|a|b|\n|-|-|\n|1|2|")
        #expect(html.contains("<table"))
        #expect(html.contains("<td") && html.contains(">1</td>"))
    }

    @Test func strikethroughAndTasks() {
        let html = PreviewRenderer.body(for: "~~x~~\n\n- [x] done")
        #expect(html.contains("<del>x</del>"))
        #expect(html.contains(#"checked="""#))
    }

    @Test func pageEscapesTitle() {
        let page = PreviewRenderer.page(for: "x", title: "A<B", css: "p{}")
        #expect(page.hasPrefix("<!doctype html>"))
        #expect(page.contains("<title>A&lt;B</title>"))
        #expect(page.contains("<style>p{}</style>"))
        #expect(page.contains(#"<article id="content">"#))
    }

    @Test func keepsTextAfterNUL() {
        #expect(PreviewRenderer.body(for: "before\u{0}after").contains("after"))
    }

    @Test func emptyMarkdown() {
        #expect(PreviewRenderer.body(for: "") == "")
    }

    // MARK: Content blocks

    /// A temporary document folder holding `files` (relative path to contents), plus a sibling `outside` folder.
    final class Folder {
        let root = FileManager.default.temporaryDirectory.appending(path: "blocks-\(UUID().uuidString)")
        var doc: URL { root.appending(path: "doc") }
        var outside: URL { root.appending(path: "outside") }
        var folder: DocumentFolder { DocumentFolder(url: doc) }

        init(_ files: [String: String]) throws {
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: doc, withIntermediateDirectories: true)
            for (path, text) in files { try write(text, to: doc.appending(path: path)) }
        }

        func write(_ text: String, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        func render(_ markdown: String) -> String { PreviewRenderer.body(for: markdown, folder: folder) }

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    @Test func embedsMarkdownFile() throws {
        let folder = try Folder(["chapter-2.md": "## Two\n\nSome *text*."])
        let html = folder.render("Intro\n\n/chapter-2.md\n\nOutro")
        #expect(html.contains(#"<div class="content-block" data-sourcepos="3:1-3:13"><h2>Two</h2>"#))
        #expect(html.contains("<p>Some <em>text</em>.</p>"))
        #expect(!html.contains("/chapter-2.md"))
    }

    @Test func embedsTextFileAsMarkdown() throws {
        let folder = try Folder(["notes/a b.txt": "plain *note*"])
        #expect(folder.render("  /notes/a b.txt  ").contains("<p>plain <em>note</em></p>"))
    }

    @Test func embedsImageThroughDocumentRelativeURL() throws {
        let folder = try Folder(["img/fig 1.png": "png"])
        let html = folder.render("/img/fig 1.png")
        #expect(html.contains(#"<p class="content-block" data-sourcepos="1:1-1:14"><img src="img/fig%201.png" alt="img/fig 1.png"></p>"#))
    }

    @Test func leavesMissingFileAsWritten() throws {
        let folder = try Folder([:])
        #expect(folder.render("/missing.md").contains(#"<p data-sourcepos="1:1-1:11">/missing.md</p>"#))
        #expect(folder.render("/missing.png").contains("<p data-sourcepos=\"1:1-1:12\">/missing.png</p>"))
    }

    @Test func ignoresUnsupportedExtensionsAndPlainSlashes() throws {
        let folder = try Folder(["data.json": "{}", "x": "x"])
        #expect(folder.render("/data.json").contains("<p data-sourcepos=\"1:1-1:10\">/data.json</p>"))
        #expect(folder.render("/x").contains("<p data-sourcepos=\"1:1-1:2\">/x</p>"))
    }

    @Test func ignoresPathsLeavingTheFolder() throws {
        let folder = try Folder([:])
        try folder.write("secret", to: folder.outside.appending(path: "x.md"))
        try FileManager.default.createSymbolicLink(at: folder.doc.appending(path: "link"), withDestinationURL: folder.outside)
        for line in ["/../outside/x.md", "/link/x.md", "//../outside/x.md"] {
            let html = folder.render(line)
            #expect(!html.contains("secret"), "\(line)")
            #expect(html.contains(">\(line)</p>"), "\(line)")
        }
    }

    @Test func pathEmbeddedInLongerParagraphIsNotABlock() throws {
        let folder = try Folder(["a.md": "EMBEDDED"])
        #expect(!folder.render("Some text\n/a.md").contains("EMBEDDED"))
        #expect(!folder.render("/a.md\n/a.md").contains("EMBEDDED"))
        #expect(!folder.render("see /a.md").contains("EMBEDDED"))
    }

    @Test func ignoresBlockLinesInCode() throws {
        let folder = try Folder(["a.md": "EMBEDDED"])
        #expect(!folder.render("```\n/a.md\n```").contains("EMBEDDED"))
        #expect(!folder.render("    /a.md").contains("EMBEDDED"))
        #expect(!folder.render("`/a.md`").contains("EMBEDDED"))
    }

    @Test func escapesEchoedPaths() throws {
        let folder = try Folder(["a&\"b.png": "png", "c&<d.md": "**ok**"])
        let html = folder.render("/a&\"b.png\n\n/c&<d.md")
        #expect(html.contains(#"<img src="a&amp;%22b.png" alt="a&amp;&quot;b.png">"#))
        #expect(html.contains("<strong>ok</strong>"))
    }

    @Test func nestedEmbedsResolveFromTheDocumentFolder() throws {
        let folder = try Folder(["parts/a.md": "A\n\n/parts/b.md", "parts/b.md": "B"])
        let html = folder.render("/parts/a.md")
        #expect(html.contains("<p>A</p>") && html.contains("<p>B</p>"))
    }

    @Test func selfInclusionTerminates() throws {
        let folder = try Folder(["self.md": "SELF\n\n/self.md"])
        let html = folder.render("/self.md")
        #expect(html.components(separatedBy: "SELF").count == 2)
        #expect(html.contains("<p>/self.md</p>"))
    }

    @Test func cycleTerminates() throws {
        let folder = try Folder(["a.md": "A\n\n/b.md", "b.md": "B\n\n/a.md"])
        let html = folder.render("/a.md")
        #expect(html.components(separatedBy: "<p>A</p>").count == 2)
        #expect(html.components(separatedBy: "<p>B</p>").count == 2)
        #expect(html.contains("<p>/a.md</p>"))
    }

    @Test func depthIsCapped() throws {
        let depth = ContentBlocks.maxDepth + 5
        var files: [String: String] = [:]
        for level in 0..<depth { files["\(level).md"] = "L\(level)\n\n/\(level + 1).md" }
        let folder = try Folder(files)
        let html = folder.render("/0.md")
        #expect(html.contains("<p>L\(ContentBlocks.maxDepth - 1)</p>"))
        #expect(!html.contains("<p>L\(ContentBlocks.maxDepth)</p>"))
    }

    @Test func keepsScrollSyncPositionsAfterAnEmbed() throws {
        let folder = try Folder(["long.md": (1...20).map { "Para \($0)" }.joined(separator: "\n\n")])
        let markdown = "# Title\n\n/long.md\n\nAfter"
        let plain = PreviewRenderer.body(for: markdown)
        let embedded = folder.render(markdown)
        let positions = { (html: String) in html.matches(of: #/data-sourcepos="([^"]+)"/#).map { String($0.1) } }
        #expect(positions(embedded) == positions(plain))
        #expect(embedded.contains(#"<p data-sourcepos="5:1-5:5">After</p>"#))
    }

    @Test func withoutFolderNothingIsEmbedded() {
        #expect(PreviewRenderer.body(for: "/a.md").contains(">/a.md</p>"))
    }

    @Test func pageEmbedsToo() throws {
        let folder = try Folder(["a.md": "EMBEDDED"])
        #expect(PreviewRenderer.page(for: "/a.md", title: "t", css: "", folder: folder.folder).contains("<p>EMBEDDED</p>"))
    }
}

