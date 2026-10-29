import Foundation

/// The folder a document lives in: the only place its images and content blocks may be read from.
public struct DocumentFolder: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The file at `relativePath`, or nil when it would leave the folder. Symlinks are resolved on both
    /// sides, so neither `..` nor a link inside the folder can point outside it.
    public func fileURL(relativePath: String) -> URL? {
        let folder = url.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = folder.appending(path: relativePath).standardizedFileURL.resolvingSymlinksInPath()
        return candidate.path.hasPrefix(folder.path + "/") ? candidate : nil
    }

    func fileExists(relativePath: String) -> Bool {
        fileURL(relativePath: relativePath).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func text(relativePath: String) -> String? {
        guard let file = fileURL(relativePath: relativePath), let data = try? Data(contentsOf: file) else { return nil }
        return TextDecoding.decode(data).text
    }
}
