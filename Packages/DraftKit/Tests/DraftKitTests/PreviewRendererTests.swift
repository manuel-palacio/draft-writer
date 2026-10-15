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
}
