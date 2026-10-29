import Foundation
import Markdown

/// Renders Markdown as a Word document (.docx). Headings, quotes and code blocks use named Word styles and
/// lists use real Word numbering, so the result stays editable in Word and Pages; links are true hyperlinks.
/// Raw HTML is left out (as in the preview) and images become their alt text.
public enum DocxRenderer {
    public static func docx(for markdown: String, title: String) -> Data {
        let body = DocxBody(markdown: markdown)
        let parts = [
            ("[Content_Types].xml", DocxParts.contentTypes),
            ("_rels/.rels", DocxParts.packageRelationships),
            ("docProps/core.xml", DocxParts.coreProperties(title: title)),
            ("word/document.xml", DocxParts.document(body: body.xml)),
            ("word/_rels/document.xml.rels", DocxParts.documentRelationships(links: body.links)),
            ("word/styles.xml", DocxParts.styles),
            ("word/numbering.xml", DocxParts.numbering(orderedLists: body.orderedLists)),
        ]
        return ZipArchive.stored(parts.map { (name: $0.0, data: Data($0.1.utf8)) })
    }
}

/// An ordered list's numbering: where it starts and how deeply it is nested. Each gets its own Word list,
/// so numbering restarts per list.
struct OrderedListNumbering: Equatable {
    let start: Int
    let level: Int
}

/// Walks the Markdown tree and writes the WordprocessingML `<w:body>` content.
struct DocxBody {
    static let bulletNumberingID = 1
    static let monospaceFont = "Menlo"

    private(set) var xml = ""
    /// Hyperlink targets; link `n` (from 1) is relationship `rIdLink<n>`.
    private(set) var links: [String] = []
    /// Ordered list `n` (from 1) is numbering ID `n + 1`; ID 1 is shared by all bulleted lists.
    private(set) var orderedLists: [OrderedListNumbering] = []
    private var listNumberingIDs: [Int] = []
    private var quoteDepth = 0
    /// Set at the start of a list item: its first paragraph carries the bullet or number.
    private var numberNextParagraph = false
    private var pendingCheckbox: Checkbox?

    init(markdown: String) {
        Document(parsing: markdown).children.forEach { renderBlock($0) }
    }

    private mutating func renderBlock(_ block: Markup) {
        switch block {
        case let heading as Heading:
            let level = min(heading.level, 6)
            // The style's look repeated as direct formatting, for readers that ignore styles (Quick Look, TextEdit).
            let format = RunFormat(bold: true, size: DocxParts.headingSizes[level - 1])
            paragraph(style: "Heading\(level)", content: inlines(of: heading, format: format))
        case let paragraphBlock as Paragraph:
            paragraph(style: quoteDepth > 0 ? "Quote" : nil, content: checkboxPrefix() + inlines(of: paragraphBlock))
        case let quote as BlockQuote:
            quoteDepth += 1
            quote.children.forEach { renderBlock($0) }
            quoteDepth -= 1
        case let list as UnorderedList:
            renderList(list, numberingID: Self.bulletNumberingID)
        case let list as OrderedList:
            orderedLists.append(OrderedListNumbering(start: Int(list.startIndex), level: listNumberingIDs.count))
            renderList(list, numberingID: orderedLists.count + 1)
        case let code as CodeBlock:
            paragraph(style: "Code", content: codeRun(code.code))
        case is ThematicBreak:
            xml += "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"auto\"/></w:pBdr></w:pPr></w:p>"
        case let table as Table:
            renderTable(table)
        default:
            block.children.forEach { renderBlock($0) }
        }
    }

    private mutating func renderList(_ list: some ListItemContainer, numberingID: Int) {
        listNumberingIDs.append(numberingID)
        for item in list.listItems {
            numberNextParagraph = true
            pendingCheckbox = item.checkbox
            item.children.forEach { renderBlock($0) }
        }
        listNumberingIDs.removeLast()
    }

    private mutating func paragraph(style: String?, content: String) {
        xml += "<w:p>\(paragraphProperties(style: style))\(content)</w:p>"
    }

    /// A list item's first paragraph is numbered; its later paragraphs are indented to line up with it.
    private mutating func paragraphProperties(style: String?) -> String {
        var properties = style.map { "<w:pStyle w:val=\"\($0)\"/>" } ?? ""
        if let numberingID = listNumberingIDs.last {
            if numberNextParagraph {
                properties += "<w:numPr><w:ilvl w:val=\"\(listNumberingIDs.count - 1)\"/><w:numId w:val=\"\(numberingID)\"/></w:numPr>"
                numberNextParagraph = false
            } else {
                properties += "<w:ind w:left=\"\(720 * listNumberingIDs.count)\"/>"
            }
        }
        return properties.isEmpty ? "" : "<w:pPr>\(properties)</w:pPr>"
    }

    private mutating func checkboxPrefix() -> String {
        defer { pendingCheckbox = nil }
        switch pendingCheckbox {
        case .checked: return Self.run("☒ ", RunFormat())
        case .unchecked: return Self.run("☐ ", RunFormat())
        case nil: return ""
        }
    }

    private func codeRun(_ code: String) -> String {
        let lines = code.hasSuffix("\n") ? String(code.dropLast()) : code
        let text = lines.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "<w:t xml:space=\"preserve\">\(DocxParts.escape(String($0)))</w:t>" }
            .joined(separator: "<w:br/>")
        return "<w:r><w:rPr>\(Self.monospaceFonts)</w:rPr>\(text)</w:r>"
    }

    private mutating func renderTable(_ table: Table) {
        let columns = max(table.maxColumnCount, 1)
        let border = "w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"BFBFBF\""
        let borders = ["top", "left", "bottom", "right", "insideH", "insideV"].map { "<w:\($0) \(border)/>" }.joined()
        xml += "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders>\(borders)</w:tblBorders></w:tblPr>"
        xml += "<w:tblGrid>" + String(repeating: "<w:gridCol w:w=\"\(9000 / columns)\"/>", count: columns) + "</w:tblGrid>"
        tableRow(Array(table.head.cells), columns: columns, format: RunFormat(bold: true))
        for row in table.body.rows { tableRow(Array(row.cells), columns: columns, format: RunFormat()) }
        xml += "</w:tbl><w:p/>"
    }

    private mutating func tableRow(_ cells: [Table.Cell], columns: Int, format: RunFormat) {
        var cellContents = cells.map { inlines(of: $0, format: format) }
        cellContents += Array(repeating: "", count: max(columns - cells.count, 0))
        xml += "<w:tr>" + cellContents.map { "<w:tc><w:p>\($0)</w:p></w:tc>" }.joined() + "</w:tr>"
    }

    // MARK: Inlines

    struct RunFormat {
        var bold = false, italic = false, strike = false, code = false, link = false
        /// In half-points; nil keeps the paragraph style's size.
        var size: Int?
    }

    private mutating func inlines(of container: Markup, format: RunFormat = RunFormat()) -> String {
        container.children.map { inline($0, format: format) }.joined()
    }

    private mutating func inline(_ markup: Markup, format: RunFormat) -> String {
        var format = format
        switch markup {
        case let text as Text: return Self.run(text.string, format)
        case let code as InlineCode:
            format.code = true
            return Self.run(code.code, format)
        case is SoftBreak: return Self.run(" ", format)
        case is LineBreak: return "<w:r><w:br/></w:r>"
        case is InlineHTML: return ""
        case is Emphasis: format.italic = true
        case is Strong: format.bold = true
        case is Strikethrough: format.strike = true
        case let link as Link:
            guard let destination = link.destination, URL(string: destination)?.scheme != nil else { break }
            links.append(destination)
            format.link = true
            return "<w:hyperlink r:id=\"rIdLink\(links.count)\">\(inlines(of: link, format: format))</w:hyperlink>"
        default: break
        }
        return inlines(of: markup, format: format)
    }

    private static let monospaceFonts = "<w:rFonts w:ascii=\"\(monospaceFont)\" w:hAnsi=\"\(monospaceFont)\" w:cs=\"\(monospaceFont)\"/>"

    private static func run(_ text: String, _ format: RunFormat) -> String {
        var properties = format.link ? "<w:rStyle w:val=\"Hyperlink\"/>" : ""
        if format.code { properties += monospaceFonts }
        if format.bold { properties += "<w:b/>" }
        if format.italic { properties += "<w:i/>" }
        if format.strike { properties += "<w:strike/>" }
        if let size = format.size { properties += "<w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/>" }
        let runProperties = properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>"
        return "<w:r>\(runProperties)<w:t xml:space=\"preserve\">\(DocxParts.escape(text))</w:t></w:r>"
    }
}
