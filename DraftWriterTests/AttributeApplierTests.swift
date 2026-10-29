import AppKit
import DraftKit
import Testing
@testable import Draft_Writer

@MainActor
@Suite struct AttributeApplierTests {
    func styledFont(_ markdown: String, at location: Int, base: NSFont) throws -> NSFont {
        let storage = NSTextStorage(string: markdown)
        AttributeApplier.applyStyles(MarkdownStyler.styles(for: markdown), to: storage,
                                     in: NSRange(location: 0, length: storage.length), baseFont: base)
        return try #require(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    }

    /// The fallback used when the iA fonts don't load, and any other non-iA font: traits come from the
    /// font descriptor, not from "Bold"/"Italic" in the font name.
    @Test(arguments: [false, true])
    func nestedBoldItalicWithNonIAFont(monospaced: Bool) throws {
        let base = monospaced ? NSFont.monospacedSystemFont(ofSize: 17, weight: .regular) : NSFont.systemFont(ofSize: 17)
        let font = try styledFont("***x***", at: 3, base: base)
        #expect(font.fontDescriptor.symbolicTraits.contains([.bold, .italic]))
        #expect(font.familyName == base.familyName)
    }

    @Test func italicInsideBoldWithNonIAFont() throws {
        let base = NSFont.systemFont(ofSize: 17)
        let font = try styledFont("**a *b* c**", at: 4, base: base)
        #expect(font.fontDescriptor.symbolicTraits.contains([.bold, .italic]))
        let boldOnly = try styledFont("**a *b* c**", at: 2, base: base)
        #expect(boldOnly.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(!boldOnly.fontDescriptor.symbolicTraits.contains(.italic))
    }

    @Test func nestedBoldItalicWithIAFont() throws {
        #expect(try styledFont("***x***", at: 3, base: Theme.font(.quattro, size: 17)).fontName == "iAWriterQuattroS-BoldItalic")
    }
}
