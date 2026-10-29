import DraftKit
import Foundation

/// The preview/export stylesheet and the `draft-asset://` URL space the preview loads from:
/// `draft-asset://doc/<relative path>` (files next to the document) and
/// `draft-asset://app/fonts/<file>` (the bundled iA fonts).
enum PreviewAssets {
    static let scheme = "draft-asset"
    static let baseURL = URL(string: "draft-asset://doc/")!

    /// The four bundled faces of each font family, as (family, file, weight, style).
    private static func faces(_ fonts: [EditorFont]) -> [(family: String, file: String, weight: String, style: String)] {
        fonts.flatMap { font in
            [("Regular", "normal", "normal"), ("Bold", "bold", "normal"),
             ("Italic", "normal", "italic"), ("BoldItalic", "bold", "italic")].map {
                (font.cssFamily, "\(font.postScriptPrefix)-\($0.0).ttf", $0.1, $0.2)
            }
        }
    }

    private static let darkColors = """
    @media (prefers-color-scheme: dark) {
      :root { --text: #dcdcdc; --muted: #8a8a8a; --rule: #3a3a3c; --code-bg: rgba(255,255,255,.07);
              --link: #74adf2; --page: #1c1c1e; }
    }
    """

    /// Stylesheet for the live preview: every family from the app bundle (loaded on use, so the font can be
    /// switched in place via `--body-font`), body text in `font`, follows light/dark appearance.
    static func previewCSS(font: EditorFont = .duo, bundle: Bundle = .main) -> String {
        let css = stylesheet(bodyFont: "var(--body-font, \"\(EditorFont.duo.cssFamily)\")", faces: faces(EditorFont.allCases),
                             bundle: bundle, dark: darkColors) { "url(\"draft-asset://app/fonts/\($0)\")" }
        return css + "\n:root { --body-font: \"\(font.cssFamily)\"; }"
    }

    /// Stylesheet for exported HTML/PDF: body text in `font`, named directly (exports may be opened by tools
    /// that drop custom properties). Only that family, and Mono when the document has code, are inlined as
    /// data URIs; always light.
    static func exportCSS(font: EditorFont = .duo, includesCode: Bool = true, bundle: Bundle = .main) -> String {
        let fonts = Array(Set([font] + (includesCode ? [.mono] : []))).sorted { $0.rawValue < $1.rawValue }
        return stylesheet(bodyFont: "\"\(font.cssFamily)\"", faces: faces(fonts), bundle: bundle, dark: "") { file in
            guard let url = bundle.url(forResource: file, withExtension: nil, subdirectory: "Fonts"),
                  let data = try? Data(contentsOf: url) else { return "local(\"\(file)\")" }
            return "url(\"data:font/ttf;base64,\(data.base64EncodedString())\")"
        }
    }

    private static func stylesheet(bodyFont: String, faces: [(family: String, file: String, weight: String, style: String)],
                                   bundle: Bundle, dark: String, source: (String) -> String) -> String {
        let template = bundle.url(forResource: "preview", withExtension: "css")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let fontFaces = faces.map {
            "@font-face { font-family: \"\($0.family)\"; src: \(source($0.file)); font-weight: \($0.weight); font-style: \($0.style); }"
        }.joined(separator: "\n")
        return template
            .replacingOccurrences(of: "/*{{body-font}}*/", with: bodyFont)
            .replacingOccurrences(of: "/*{{font-face}}*/", with: fontFaces)
            .replacingOccurrences(of: "/*{{dark}}*/", with: dark)
    }

    /// Maps a `draft-asset://` URL to a local file, or nil when it is unknown or would leave its folder.
    static func fileURL(for url: URL, documentFolder: URL?, bundle: Bundle) -> URL? {
        guard url.scheme == scheme else { return nil }
        let path = url.path(percentEncoded: false)
        switch url.host() {
        case "doc":
            guard let documentFolder, path.hasPrefix("/"), !path.hasPrefix("//") else { return nil }
            return DocumentFolder(url: documentFolder).fileURL(relativePath: String(path.dropFirst()))
        case "app":
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].isEmpty, parts[1] == "fonts", !parts[2].isEmpty, parts[2] != ".." else {
                return nil
            }
            return bundle.url(forResource: String(parts[2]), withExtension: nil, subdirectory: "Fonts")
        default:
            return nil
        }
    }
}

extension EditorFont {
    /// The CSS font-family name the preview and exports declare for this font.
    var cssFamily: String { "iA Writer \(displayName)" }
}
