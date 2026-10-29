import Foundation
import Observation

enum TemplateFolderError: LocalizedError {
    case noStylesheet

    var errorDescription: String? { "The folder has no .css files." }
}

/// The user's preview and export template: a folder of CSS that replaces the built-in stylesheet (fonts,
/// dark mode and all). Every `.css` file directly inside the folder is used, sorted by name and joined, so a
/// template can be split into parts. Kept across launches as a security-scoped bookmark; a folder that can
/// no longer be read falls back to the built-in stylesheet. The CSS is read when the folder is chosen and at launch.
@MainActor @Observable
final class TemplateFolder {
    static let shared = TemplateFolder(defaults: .standard)
    static let bookmarkKey = "templateFolderBookmark"

    private(set) var url: URL?
    /// The template's stylesheet, or nil for the built-in one.
    private(set) var css: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func choose(_ folder: URL) throws {
        let css = try Self.stylesheet(in: folder)
        defaults.set(try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil),
                     forKey: Self.bookmarkKey)
        url = folder
        self.css = css
    }

    func restore() {
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                                    bookmarkDataIsStale: &isStale),
              let css = Self.readStylesheet(in: folder) else {
            useBuiltIn()
            return
        }
        url = folder
        self.css = css
    }

    func useBuiltIn() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        url = nil
        css = nil
    }

    private static func readStylesheet(in folder: URL) -> String? {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        return try? stylesheet(in: folder)
    }

    static func stylesheet(in folder: URL) throws -> String {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "css" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !files.isEmpty else { throw TemplateFolderError.noStylesheet }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }
}
