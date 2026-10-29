import Foundation

/// The library's notes held in memory, already case- and diacritic-folded, so a query is a scan of strings
/// instead of a read of every file. `refresh()` re-reads only notes whose size or modification date changed.
public struct LibraryIndex: Sendable {
    public let root: URL
    /// Sorted by path, so a query keeps that order without sorting.
    private var entries: [Entry] = []

    private struct Entry: Sendable {
        let url: URL
        let path: String
        let modified: Date
        let size: Int
        let foldedName: [UInt8]
        /// nil for notes larger than `Library.maxSearchFileSize`: they match by name only.
        let foldedText: [UInt8]?
    }

    private static let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]

    public init(root: URL) {
        self.root = root
    }

    /// Brings the index in line with the folder: new and changed notes are read, deleted ones dropped.
    public mutating func refresh() {
        let known = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var readAny = false
        let current = noteURLs().compactMap { url -> Entry? in
            guard let values = try? url.resourceValues(forKeys: Self.keys) else { return nil }
            let modified = values.contentModificationDate ?? .distantPast
            let size = values.fileSize ?? 0
            if let entry = known[url.path], entry.modified == modified, entry.size == size { return entry }
            readAny = true
            return Self.entry(for: url, modified: modified, size: size)
        }
        // Sorting with `localizedStandardCompare` dominates an unchanged refresh, so skip it when the notes are the same.
        guard readAny || current.count != entries.count else { return }
        entries = current.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Notes whose name contains `query`, then notes whose text does (case- and diacritic-insensitive),
    /// each group sorted by path.
    public func search(_ query: String) -> [URL] {
        let needle = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        var byName: [URL] = []
        var byText: [URL] = []
        for entry in entries {
            if Self.bytes(entry.foldedName, contain: needle) {
                byName.append(entry.url)
            } else if let text = entry.foldedText, Self.bytes(text, contain: needle) {
                byText.append(entry.url)
            }
        }
        return byName + byText
    }

    private func noteURLs() -> [URL] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(Self.keys),
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
        return (enumerator?.allObjects ?? []).compactMap { $0 as? URL }.filter(Library.isNote)
    }

    private static func entry(for url: URL, modified: Date, size: Int) -> Entry {
        let text = size <= Library.maxSearchFileSize ? (try? Data(contentsOf: url)).map { TextDecoding.decode($0).text } : nil
        return Entry(url: url, path: url.path, modified: modified, size: size,
                     foldedName: fold(url.deletingPathExtension().lastPathComponent), foldedText: text.map(fold))
    }

    /// UTF-8 bytes, because a byte search is many times faster than `String.contains` on Foundation strings.
    private static func fold(_ string: String) -> [UInt8] {
        Array(string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).utf8)
    }

    private static func bytes(_ haystack: [UInt8], contain needle: [UInt8]) -> Bool {
        haystack.withUnsafeBytes { haystack in
            needle.withUnsafeBytes { needle in
                memmem(haystack.baseAddress, haystack.count, needle.baseAddress, needle.count) != nil
            }
        }
    }
}
