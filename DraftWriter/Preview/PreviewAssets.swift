import Foundation

/// The preview/export stylesheet and the `draft-asset://` URL space the preview loads from:
/// `draft-asset://doc/<relative path>` (files next to the document) and
/// `draft-asset://app/fonts/<file>` (the bundled iA fonts).
enum PreviewAssets {
    static let scheme = "draft-asset"
    static let baseURL = URL(string: "draft-asset://doc/")!

    private static let faces: [(family: String, file: String, weight: String, style: String)] = [
        ("iA Writer Duo", "iAWriterDuoS-Regular.ttf", "normal", "normal"),
        ("iA Writer Duo", "iAWriterDuoS-Bold.ttf", "bold", "normal"),
        ("iA Writer Duo", "iAWriterDuoS-Italic.ttf", "normal", "italic"),
        ("iA Writer Duo", "iAWriterDuoS-BoldItalic.ttf", "bold", "italic"),
        ("iA Writer Mono", "iAWriterMonoS-Regular.ttf", "normal", "normal"),
    ]

    private static let darkColors = """
    @media (prefers-color-scheme: dark) {
      :root { --text: #dcdcdc; --muted: #8a8a8a; --rule: #3a3a3c; --code-bg: rgba(255,255,255,.07);
              --link: #74adf2; --page: #1c1c1e; }
    }
    """

    /// Stylesheet for the live preview: fonts from the app bundle, follows light/dark appearance.
    static func previewCSS(bundle: Bundle = .main) -> String {
        stylesheet(bundle: bundle, dark: darkColors) { "url(\"draft-asset://app/fonts/\($0)\")" }
    }

    /// Stylesheet for exported HTML/PDF: fonts inlined as data URIs, always light.
    static func exportCSS(bundle: Bundle = .main) -> String {
        stylesheet(bundle: bundle, dark: "") { file in
            guard let url = bundle.url(forResource: file, withExtension: nil, subdirectory: "Fonts"),
                  let data = try? Data(contentsOf: url) else { return "local(\"\(file)\")" }
            return "url(\"data:font/ttf;base64,\(data.base64EncodedString())\")"
        }
    }

    private static func stylesheet(bundle: Bundle, dark: String, source: (String) -> String) -> String {
        let template = bundle.url(forResource: "preview", withExtension: "css")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let fontFaces = faces.map {
            "@font-face { font-family: \"\($0.family)\"; src: \(source($0.file)); font-weight: \($0.weight); font-style: \($0.style); }"
        }.joined(separator: "\n")
        return template
            .replacingOccurrences(of: "/*{{font-face}}*/", with: fontFaces)
            .replacingOccurrences(of: "/*{{dark}}*/", with: dark)
    }

    /// Maps a `draft-asset://` URL to a local file, or nil when it is unknown or would leave its folder.
    static func fileURL(for url: URL, documentFolder: URL?, bundle: Bundle) -> URL? {
        guard url.scheme == scheme else { return nil }
        let path = url.path(percentEncoded: false)
        switch url.host() {
        case "doc":
            guard let folder = documentFolder?.standardizedFileURL, path.hasPrefix("/"), !path.hasPrefix("//") else {
                return nil
            }
            let candidate = folder.appending(path: String(path.dropFirst())).standardizedFileURL
            return candidate.path.hasPrefix(folder.path + "/") ? candidate : nil
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
