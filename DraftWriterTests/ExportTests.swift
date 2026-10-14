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

    @Test func pdfContainsText() async throws {
        let url = tempURL("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await Exporter.writePDF(source, to: url, pageSize: .a4)
        #expect(PDFDocument(url: url)?.string?.contains("Part 1") == true)
    }
}
