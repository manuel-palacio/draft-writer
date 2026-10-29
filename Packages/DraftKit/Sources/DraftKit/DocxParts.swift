import Foundation

/// The fixed and generated XML parts of a .docx package, apart from the document body.
enum DocxParts {
    private static let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    private static let wordNamespace = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
    private static let relationshipTypes = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    static let contentTypes = header + """
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
    <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>\
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
    </Types>
    """

    static let packageRelationships = header + """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="\(relationshipTypes)/officeDocument" Target="word/document.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
    </Relationships>
    """

    static func coreProperties(title: String) -> String {
        header + """
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>\(escape(title))</dc:title></cp:coreProperties>
        """
    }

    static func document(body: String) -> String {
        header + """
        <w:document \(wordNamespace) xmlns:r="\(relationshipTypes)"><w:body>\(body)\
        <w:sectPr><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="567" w:footer="567" w:gutter="0"/></w:sectPr>\
        </w:body></w:document>
        """
    }

    static func documentRelationships(links: [String]) -> String {
        let hyperlinks = links.enumerated().map { index, url in
            "<Relationship Id=\"rIdLink\(index + 1)\" Type=\"\(relationshipTypes)/hyperlink\" Target=\"\(escape(url))\" TargetMode=\"External\"/>"
        }
        return header + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rIdStyles" Type="\(relationshipTypes)/styles" Target="styles.xml"/>\
        <Relationship Id="rIdNumbering" Type="\(relationshipTypes)/numbering" Target="numbering.xml"/>\
        \(hyperlinks.joined())</Relationships>
        """
    }

    /// Heading 1–6 sizes in half-points: 20, 16, 13 pt, then the 11 pt body size.
    static let headingSizes = [40, 32, 26, 22, 22, 22]

    static let styles: String = {
        let headings = headingSizes.enumerated().map { index, size in
            """
            <w:style w:type="paragraph" w:styleId="Heading\(index + 1)"><w:name w:val="heading \(index + 1)"/>\
            <w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>\
            <w:pPr><w:keepNext/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="\(index)"/></w:pPr>\
            <w:rPr><w:b/><w:sz w:val="\(size)"/><w:szCs w:val="\(size)"/></w:rPr></w:style>
            """
        }
        let monospace = DocxBody.monospaceFont
        return header + """
        <w:styles \(wordNamespace)>\
        <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Helvetica" w:hAnsi="Helvetica" w:cs="Helvetica"/>\
        <w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault>\
        <w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>\
        \(headings.joined())\
        <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:qFormat/>\
        <w:pPr><w:ind w:left="720"/></w:pPr><w:rPr><w:i/><w:color w:val="595959"/></w:rPr></w:style>\
        <w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:qFormat/>\
        <w:pPr><w:spacing w:after="160" w:line="240" w:lineRule="auto"/></w:pPr>\
        <w:rPr><w:rFonts w:ascii="\(monospace)" w:hAnsi="\(monospace)" w:cs="\(monospace)"/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>\
        <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/>\
        <w:rPr><w:color w:val="1A6BBF"/><w:u w:val="single"/></w:rPr></w:style>\
        </w:styles>
        """
    }()

    /// Abstract list 0 is bullets, 1 is decimal numbers, each with nine levels. Bulleted lists share list 1;
    /// each ordered list gets its own list (ID 2, 3, …) that restarts at its first number.
    static func numbering(orderedLists: [OrderedListNumbering]) -> String {
        let bullets = ["•", "◦", "▪"]
        let bulletLevels = (0..<9).map { level(index: $0, format: "bullet", text: bullets[$0 % 3]) }.joined()
        let decimalLevels = (0..<9).map { level(index: $0, format: "decimal", text: "%\($0 + 1).") }.joined()
        let orderedNums = orderedLists.enumerated().map { index, list in
            """
            <w:num w:numId="\(index + 2)"><w:abstractNumId w:val="1"/>\
            <w:lvlOverride w:ilvl="\(list.level)"><w:startOverride w:val="\(list.start)"/></w:lvlOverride></w:num>
            """
        }
        return header + """
        <w:numbering \(wordNamespace)>\
        <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>\(bulletLevels)</w:abstractNum>\
        <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>\(decimalLevels)</w:abstractNum>\
        <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>\(orderedNums.joined())</w:numbering>
        """
    }

    private static func level(index: Int, format: String, text: String) -> String {
        """
        <w:lvl w:ilvl="\(index)"><w:start w:val="1"/><w:numFmt w:val="\(format)"/><w:lvlText w:val="\(text)"/>\
        <w:lvlJc w:val="left"/><w:pPr><w:ind w:left="\(720 * (index + 1))" w:hanging="360"/></w:pPr></w:lvl>
        """
    }

    /// Escapes text for XML and drops the control characters XML 1.0 cannot represent.
    static func escape(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { $0.value >= 0x20 || [0x9, 0xA, 0xD].contains($0.value) })
        return String(scalars)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
