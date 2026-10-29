import AppKit
import DraftKit

/// Turns `MarkdownStyler` output into display attributes on the text storage.
/// Attribute-only edits on `NSTextStorage` change neither the characters, the undo stack,
/// nor the document's edited state.
@MainActor
enum AttributeApplier {
    static func applyStyles(_ styles: [StyledRange], to storage: NSTextStorage, in range: NSRange, baseFont: NSFont) {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        storage.beginEditing()
        storage.setAttributes(DraftTextView.baseAttributes(font: baseFont), range: range)
        for styled in styles {
            let r = NSIntersectionRange(styled.range, range)
            guard r.length > 0 else { continue }
            apply(styled.style, to: storage, in: r, baseFont: baseFont)
        }
        storage.endEditing()
    }

    private static func apply(_ style: MarkdownStyle, to storage: NSTextStorage, in r: NSRange, baseFont: NSFont) {
        let size = baseFont.pointSize
        switch style {
        case .heading(let level):
            let scale: CGFloat = level == 1 ? 1.3 : level == 2 ? 1.15 : 1.0
            storage.addAttribute(.font, value: font(like: baseFont, size: size * scale, bold: true, italic: false), range: r)
        case .strong:
            restyleFonts(storage, r) { font(like: $0, size: $0.pointSize, bold: true, italic: isItalic($0)) }
        case .emphasis:
            restyleFonts(storage, r) { font(like: $0, size: $0.pointSize, bold: isBold($0), italic: true) }
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        case .inlineCode, .codeBlock:
            storage.addAttribute(.font, value: Theme.font(.mono, size: size), range: r)
            storage.addAttribute(.backgroundColor, value: Theme.codeBackground, range: r)
        case .link, .wikilink:
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            storage.addAttribute(.underlineColor, value: Theme.marker, range: r)
        case .tag:
            storage.addAttribute(.foregroundColor, value: Theme.link, range: r)
        case .listMarker:
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: r)
            applyHangingIndent(after: r, in: storage, baseFont: baseFont)
        case .linkDestination, .syntaxMarker:
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: r)
            storage.removeAttribute(.underlineStyle, range: r)
        case .blockQuote:
            break
        }
    }

    /// Wrapped lines of a list item line up with its text, not with the marker.
    private static func applyHangingIndent(after marker: NSRange, in storage: NSTextStorage, baseFont: NSFont) {
        let ns = storage.string as NSString
        let prefix = ns.substring(with: marker) + " "
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Theme.lineHeightMultiple
        style.headIndent = (prefix as NSString).size(withAttributes: [.font: baseFont]).width
        storage.addAttribute(.paragraphStyle, value: style, range: ns.paragraphRange(for: marker))
    }

    // MARK: Fonts

    private static func restyleFonts(_ storage: NSTextStorage, _ r: NSRange, _ transform: (NSFont) -> NSFont) {
        storage.enumerateAttribute(.font, in: r) { value, sub, _ in
            guard let current = value as? NSFont else { return }
            storage.addAttribute(.font, value: transform(current), range: sub)
        }
    }

    private static func isBold(_ font: NSFont) -> Bool { font.fontDescriptor.symbolicTraits.contains(.bold) }
    private static func isItalic(_ font: NSFont) -> Bool { font.fontDescriptor.symbolicTraits.contains(.italic) }

    /// Same family as `base`, with the requested face: the bundled iA face, or for any other font (such as
    /// the system fallback when the iA fonts don't load) `base` with its bold and italic traits replaced.
    private static func font(like base: NSFont, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        if let family = EditorFont.allCases.first(where: { base.fontName.hasPrefix($0.postScriptPrefix + "-") }) {
            return Theme.font(family, size: size, bold: bold, italic: italic)
        }
        var traits = base.fontDescriptor.symbolicTraits.subtracting([.bold, .italic])
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
    }
}
