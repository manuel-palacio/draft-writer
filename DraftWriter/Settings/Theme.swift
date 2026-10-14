import AppKit

enum EditorFont: String, CaseIterable, Identifiable {
    case duo, mono, quattro

    var id: Self { self }

    var displayName: String {
        switch self {
        case .duo: "Duo"
        case .mono: "Mono"
        case .quattro: "Quattro"
        }
    }

    /// PostScript name prefix of the bundled static iA fonts, e.g. "iAWriterDuoS-Regular".
    fileprivate var postScriptPrefix: String {
        switch self {
        case .duo: "iAWriterDuoS"
        case .mono: "iAWriterMonoS"
        case .quattro: "iAWriterQuattroS"
        }
    }
}

enum Theme {
    static let lineHeightMultiple: CGFloat = 1.5
    static let minimumMargin: CGFloat = 24

    static func font(_ font: EditorFont, size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let face = switch (bold, italic) {
        case (false, false): "Regular"
        case (true, false): "Bold"
        case (false, true): "Italic"
        case (true, true): "BoldItalic"
        }
        return NSFont(name: "\(font.postScriptPrefix)-\(face)", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    /// Horizontal inset that keeps a column of `columns` characters centred in a view of `viewWidth`.
    static func columnInset(viewWidth: CGFloat, font: NSFont, columns: Int) -> CGFloat {
        let characterWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        return max(minimumMargin, (viewWidth - CGFloat(columns) * characterWidth) / 2)
    }

    // Colours adapt to light and dark appearance.
    static let text = dynamic(light: NSColor(white: 0.13, alpha: 1), dark: NSColor(white: 0.86, alpha: 1))
    static let dimmed = dynamic(light: NSColor(white: 0.13, alpha: 0.3), dark: NSColor(white: 0.86, alpha: 0.3))
    static let marker = dynamic(light: NSColor(white: 0.62, alpha: 1), dark: NSColor(white: 0.45, alpha: 1))
    static let link = dynamic(light: NSColor(srgbRed: 0.10, green: 0.42, blue: 0.75, alpha: 1),
                              dark: NSColor(srgbRed: 0.45, green: 0.68, blue: 0.95, alpha: 1))
    static let codeBackground = dynamic(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.07))
    static let background = dynamic(light: NSColor(srgbRed: 0.98, green: 0.98, blue: 0.97, alpha: 1),
                                    dark: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}
