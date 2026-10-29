import Foundation
import PDFKit
import Testing
@testable import Draft_Writer

@MainActor
@Suite struct ExportTests {
    let source = ExportSource(
        markdown: (1...150).map { "## Part \($0)\n\nSome *words* in a paragraph that goes on for a while, twenty words or so in total here." }
            .joined(separator: "\n\n"),
        title: "Long <Doc>", documentFolder: nil)

    func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).\(ext)")
    }

    @Test func htmlIsSelfContained() {
        let html = Exporter.html(source)
        #expect(html.contains("<style>"))
        #expect(html.contains("data:font/ttf;base64,"))
        #expect(!html.contains("draft-asset:"))
        #expect(html.contains("<title>Long &lt;Doc&gt;</title>"))
    }

    @Test func htmlUsesChosenFont() {
        let html = Exporter.html(ExportSource(markdown: "Hi", title: "x", documentFolder: nil, font: .quattro))
        #expect(html.contains("17px/1.6 \"iA Writer Quattro\""))
        #expect(!html.contains("@font-face { font-family: \"iA Writer Mono\""))
        let withCode = Exporter.html(ExportSource(markdown: "Run `ls`", title: "x", documentFolder: nil, font: .quattro))
        #expect(withCode.contains("@font-face { font-family: \"iA Writer Mono\""))
    }

    @Test func htmlEmbedsContentBlocksFromTheDocumentFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "export-blocks-\(UUID().uuidString)")
        let doc = root.appending(path: "doc")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: doc, withIntermediateDirectories: true)
        try "Embedded *chapter*".write(to: doc.appending(path: "chapter.md"), atomically: true, encoding: .utf8)
        try "Secret".write(to: root.appending(path: "secret.md"), atomically: true, encoding: .utf8)
        try "png".write(to: doc.appending(path: "fig.png"), atomically: true, encoding: .utf8)
        let html = Exporter.html(ExportSource(markdown: "/chapter.md\n\n/../secret.md\n\n/fig.png", title: "x", documentFolder: doc))
        #expect(html.contains("Embedded <em>chapter</em>"))
        #expect(!html.contains("<p>Secret</p>") && html.contains(">/../secret.md</p>"))
        #expect(html.contains(#"<img src="fig.png""#))
    }

    @Test func htmlUsesTemplateStylesheetInsteadOfBuiltIn() {
        let template = "body { color: rgb(1, 2, 3) }"
        let html = Exporter.html(ExportSource(markdown: "Run `ls`", title: "x", documentFolder: nil, templateCSS: template))
        #expect(html.contains("<style>\(template)</style>"))
        #expect(!html.contains("data:font/ttf;base64,"))
        #expect(!html.contains("iA Writer"))
    }

    @Test func pdfUsesTemplateStylesheet() async throws {
        let url = tempURL("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let template = "body { font-family: Courier; } h1 { display: none; }"
        try await Exporter.writePDF(ExportSource(markdown: "# Hidden\n\nShown", title: "x", documentFolder: nil, templateCSS: template),
                                    to: url, pageSize: .a4)
        let text = PDFDocument(url: url)?.string ?? ""
        #expect(text.contains("Shown"))
        #expect(!text.contains("Hidden"))
    }

    @Test func pdfIsPaginatedA4() async throws {
        let url = tempURL("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await Exporter.writePDF(source, to: url, pageSize: .a4)
        let pdf = try #require(PDFDocument(url: url))
        #expect(pdf.pageCount > 1)
        let box = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - 595) <= 1 && abs(box.height - 842) <= 1)
    }

    @Test func pdfLetter() async throws {
        let url = tempURL("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await Exporter.writePDF(source, to: url, pageSize: .letter)
        let box = try #require(PDFDocument(url: url)?.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - 612) <= 1 && abs(box.height - 792) <= 1)
    }

    @Test func pdfHasTwoCentimetreMargins() async throws {
        let url = tempURL("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await Exporter.writePDF(source, to: url, pageSize: .a4)
        let pdf = try #require(PDFDocument(url: url))
        let page = try #require(pdf.page(at: 0))
        let selection = try #require(pdf.findString("Part 1", withOptions: []).first)
        let bounds = selection.bounds(for: page)
        #expect(bounds.minX >= 50, "text starts at x=\(bounds.minX)")
        #expect(bounds.maxY <= page.bounds(for: .mediaBox).height - 50, "text top at y=\(bounds.maxY)")
    }

    @Test func pdfContainsText() async throws {
        let url = tempURL("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await Exporter.writePDF(source, to: url, pageSize: .a4)
        #expect(PDFDocument(url: url)?.string?.contains("Part 1") == true)
    }
}

@MainActor
@Suite struct WordExportTests {
    let markdown = """
    # Big Title

    Some **strong** and *em* text, a [link](https://example.com/page) and `code()`.

    - item one
      - nested item
    - item two

    1. first
    2. second

    ```
    let x = 1
    ```
    """

    var docx: Data { Exporter.docx(ExportSource(markdown: markdown, title: "Doc", documentFolder: nil)) }

    func readBack() throws -> NSAttributedString {
        try NSAttributedString(data: docx, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                               documentAttributes: nil)
    }

    func attributes(of text: String, in document: NSAttributedString) throws -> [NSAttributedString.Key: Any] {
        let range = (document.string as NSString).range(of: text)
        try #require(range.location != NSNotFound, "\(text) missing from \(document.string)")
        return document.attributes(at: range.location, effectiveRange: nil)
    }

    func font(of text: String, in document: NSAttributedString) throws -> NSFont {
        try #require(try attributes(of: text, in: document)[.font] as? NSFont)
    }

    @Test func isAZipWithTheWordParts() {
        let data = docx
        #expect(data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(data.range(of: Data("word/document.xml".utf8)) != nil)
        #expect(data.range(of: Data("[Content_Types].xml".utf8)) != nil)
    }

    @Test func keepsEmphasisAndStrong() throws {
        let document = try readBack()
        #expect(try font(of: "strong", in: document).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(try font(of: "em", in: document).fontDescriptor.symbolicTraits.contains(.italic))
        #expect(try !font(of: "Some", in: document).fontDescriptor.symbolicTraits.contains(.bold))
    }

    /// The ZIP's entries are stored uncompressed, so a part can be read straight from its local header
    /// (the test bundle runs sandboxed and cannot shell out to `unzip`).
    func part(_ name: String) throws -> XMLDocument {
        let data = docx
        var offset = 0
        func uint(_ at: Int, _ width: Int) -> Int {
            (0..<width).reduce(0) { $0 | Int(data[data.startIndex + at + $1]) << (8 * $1) }
        }
        while uint(offset, 4) == 0x0403_4B50 {
            let size = uint(offset + 18, 4), nameLength = uint(offset + 26, 2), extraLength = uint(offset + 28, 2)
            let start = offset + 30 + nameLength + extraLength
            if String(decoding: data[offset + 30 ..< offset + 30 + nameLength], as: UTF8.self) == name {
                return try XMLDocument(data: data[start ..< start + size])
            }
            offset = start + size
        }
        throw CocoaError(.fileNoSuchFile)
    }

    /// Cocoa's Word importer ignores hyperlinks (in every OOXML form), so links are checked in the XML itself.
    @Test func keepsLinks() throws {
        let document = try part("word/document.xml")
        let hyperlink = try #require(try document.nodes(forXPath: "//*[local-name()='hyperlink']").first as? XMLElement)
        #expect(hyperlink.stringValue == "link")
        let id = try #require(hyperlink.attributes?.first { $0.localName == "id" }?.stringValue)
        let target = try part("word/_rels/document.xml.rels")
            .nodes(forXPath: "//*[local-name()='Relationship'][@Id='\(id)']/@Target").first?.stringValue
        #expect(target == "https://example.com/page")
    }

    @Test func keepsListsAndNesting() throws {
        let document = try readBack()
        let top = try #require(try attributes(of: "item one", in: document)[.paragraphStyle] as? NSParagraphStyle)
        let nested = try #require(try attributes(of: "nested item", in: document)[.paragraphStyle] as? NSParagraphStyle)
        let numbered = try #require(try attributes(of: "second", in: document)[.paragraphStyle] as? NSParagraphStyle)
        #expect(top.textLists.count == 1)
        #expect(nested.textLists.count == 2)
        #expect(numbered.textLists.count == 1)
    }

    /// Cocoa's importer reads every list as bulleted, so the number format is checked in the XML itself.
    @Test func orderedListsAreNumbered() throws {
        let numberingID = try part("word/document.xml")
            .nodes(forXPath: "//*[local-name()='p'][contains(., 'second')]//*[local-name()='numId']/@*[local-name()='val']")
            .first?.stringValue
        let numbering = try part("word/numbering.xml")
        let abstractID = try numbering
            .nodes(forXPath: "//*[local-name()='num'][@*[local-name()='numId']='\(try #require(numberingID))']/*[local-name()='abstractNumId']/@*[local-name()='val']")
            .first?.stringValue
        let format = try numbering
            .nodes(forXPath: "//*[local-name()='abstractNum'][@*[local-name()='abstractNumId']='\(try #require(abstractID))']/*[local-name()='lvl'][1]/*[local-name()='numFmt']/@*[local-name()='val']")
            .first?.stringValue
        #expect(format == "decimal")
    }

    @Test func codeIsMonospaced() throws {
        let document = try readBack()
        #expect(try font(of: "code()", in: document).isFixedPitch)
        #expect(try font(of: "let x = 1", in: document).isFixedPitch)
    }

    @Test func headingIsLargerAndBold() throws {
        let document = try readBack()
        let heading = try font(of: "Big Title", in: document)
        #expect(heading.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(heading.pointSize > (try font(of: "Some", in: document)).pointSize)
    }
}

@MainActor
@Suite struct PrintHostingTests {
    @Test func interactivePrintUsesKeyWindow() {
        let offscreen = NSWindow()
        let key = NSWindow()
        #expect(Exporter.panelWindow(interactive: true, offscreen: offscreen, key: key) === key)
        #expect(Exporter.panelWindow(interactive: true, offscreen: offscreen, key: nil) === offscreen)
        #expect(Exporter.panelWindow(interactive: false, offscreen: offscreen, key: key) === offscreen)
    }

    @Test func exportFailsInsteadOfHangingWhenWebProcessDies() async {
        let page = PrintPage(source: ExportSource(markdown: "# x", title: "x", documentFolder: nil))
        let loading = Task { try await page.load() }
        while page.webView == nil { await Task.yield() }
        page.webViewWebContentProcessDidTerminate(page.webView!)
        await #expect(throws: ExportError.self) { _ = try await loading.value }
    }
}
