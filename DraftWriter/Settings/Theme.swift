import AppKit
import DraftKit

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
    var postScriptPrefix: String {
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

    // Part-of-speech colours (light, dark). Dimmed variants keep the hue at focus-mode opacity.
    private static let highlightHues: [LexicalClass: (light: UInt32, dark: UInt32)] = [
        .noun: (0xC2410C, 0xF0915A), .verb: (0x2563EB, 0x7AA7F7), .adjective: (0xA16207, 0xE0B04A),
        .adverb: (0x9333EA, 0xC08AF5), .conjunction: (0x059669, 0x4CC9A0),
    ]

    // Style-check colours, apart from the part-of-speech hues: slate fillers, cyan clichés, crimson redundancies.
    private static let styleCheckHues: [StyleCheck: (light: UInt32, dark: UInt32)] = [
        .filler: (0x64748B, 0x94A3B8), .cliche: (0x0891B2, 0x22D3EE), .redundancy: (0xE11D48, 0xFB7185),
    ]

    private static let highlightColors = highlightHues.mapValues(colorPair)
    private static let styleCheckColors = styleCheckHues.mapValues(colorPair)

    static func highlight(_ lexicalClass: LexicalClass, dimmed: Bool) -> NSColor {
        let colors = highlightColors[lexicalClass]!
        return dimmed ? colors.dimmed : colors.normal
    }

    static func highlight(_ check: StyleCheck, dimmed: Bool) -> NSColor {
        let colors = styleCheckColors[check]!
        return dimmed ? colors.dimmed : colors.normal
    }

    /// A hue at full strength and at focus-mode opacity, each adapting to light and dark appearance.
    private static func colorPair(_ hue: (light: UInt32, dark: UInt32)) -> (normal: NSColor, dimmed: NSColor) {
        func rgb(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                     blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        return (dynamic(light: rgb(hue.light, 1), dark: rgb(hue.dark, 1)),
                dynamic(light: rgb(hue.light, 0.3), dark: rgb(hue.dark, 0.3)))
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}
