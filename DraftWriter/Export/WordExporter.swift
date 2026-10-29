import DraftKit
import Foundation

extension Exporter {
    /// A Word document of the source. Built from the Markdown itself, not the HTML, so headings, lists and
    /// links come out as real Word styles, numbering and hyperlinks; the stylesheet does not apply.
    static func docx(_ source: ExportSource) -> Data {
        DocxRenderer.docx(for: source.markdown, title: source.title)
    }
}
