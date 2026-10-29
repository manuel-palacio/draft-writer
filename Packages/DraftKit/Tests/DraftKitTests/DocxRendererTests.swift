import Foundation
import Testing
@testable import DraftKit

@Suite struct DocxRendererTests {
    func body(_ markdown: String) -> DocxBody {
        DocxBody(markdown: markdown)
    }

    @Test func crcMatchesTheStandardCheckValue() {
        #expect(ZipArchive.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func archivePassesUnzipIntegrityCheck() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "docx-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: url) }
        try DocxRenderer.docx(for: "# Hi\n\n- a\n- b\n\n[x](https://example.com)", title: "T").write(to: url)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-tq", url.path]
        unzip.standardOutput = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0)
    }

    @Test func everyPartIsWellFormedXML() throws {
        let markdown = "# T & \"q\"\n\n> quote *x*\n\n1. a\n   - b [l](https://e.com/?a=1&b=2)\n\n- [ ] task\n\n"
            + "|a|b|\n|-|-|\n|1|\n\n---\n\n```\n<tag>\n```\n\n![alt](i.png) <b>raw</b>"
        let url = FileManager.default.temporaryDirectory.appending(path: "docx-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: url) }
        try DocxRenderer.docx(for: markdown, title: "<T>").write(to: url)
        for part in ["[Content_Types].xml", "_rels/.rels", "docProps/core.xml", "word/document.xml",
                     "word/_rels/document.xml.rels", "word/styles.xml", "word/numbering.xml"] {
            let unzip = Process()
            let output = Pipe()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-p", url.path, part.replacingOccurrences(of: "[", with: "\\[")]
            unzip.standardOutput = output
            try unzip.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            unzip.waitUntilExit()
            #expect(!data.isEmpty, "\(part) missing")
            #expect(throws: Never.self, "\(part) is not well-formed") { try XMLDocument(data: data) }
        }
    }

    @Test func headingsUseWordHeadingStyles() {
        #expect(body("## Sub").xml.contains("<w:pStyle w:val=\"Heading2\"/>"))
    }

    @Test func nestedListItemsGoOneLevelDeeper() {
        let xml = body("- a\n  - b").xml
        #expect(xml.contains("<w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/>"))
        #expect(xml.contains("<w:ilvl w:val=\"1\"/><w:numId w:val=\"1\"/>"))
    }

    @Test func eachOrderedListRestartsAtItsStart() {
        let rendered = body("1. a\n\npara\n\n3. b\n   1. c")
        #expect(rendered.orderedLists == [.init(start: 1, level: 0), .init(start: 3, level: 0), .init(start: 1, level: 1)])
        let numbering = DocxParts.numbering(orderedLists: rendered.orderedLists)
        #expect(numbering.contains("<w:num w:numId=\"3\"><w:abstractNumId w:val=\"1\"/><w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"3\"/>"))
    }

    @Test func linksBecomeHyperlinkRelationships() {
        let rendered = body("[a](https://example.com/?q=1&r=2) and [local](other.md)")
        #expect(rendered.links == ["https://example.com/?q=1&r=2"])   // relative links have no meaning outside the folder
        #expect(rendered.xml.contains("<w:hyperlink r:id=\"rIdLink1\">"))
        #expect(DocxParts.documentRelationships(links: rendered.links).contains("Target=\"https://example.com/?q=1&amp;r=2\""))
    }

    @Test func escapesTextAndDropsInvalidControlCharacters() {
        let xml = body("a < b & \u{1}c").xml
        #expect(xml.contains("a &lt; b &amp; c"))
    }

    @Test func taskItemsShowTheirCheckbox() {
        let xml = body("- [x] done\n- [ ] todo").xml
        #expect(xml.contains("☒ ") && xml.contains("☐ "))
    }

    @Test func tablesBecomeWordTables() {
        let xml = body("|a|b|\n|-|-|\n|1|2|").xml
        #expect(xml.contains("<w:tbl>"))
        #expect(xml.components(separatedBy: "<w:tc>").count - 1 == 4)
    }
}
