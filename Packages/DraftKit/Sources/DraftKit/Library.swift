import Foundation

public struct LibraryItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let isFolder: Bool
    public let modified: Date
    /// Folder contents; nil for files (so `OutlineGroup` shows no disclosure triangle).
    public var children: [LibraryItem]?
    public var id: URL { url }
}

public enum LibrarySort: String, CaseIterable, Sendable {
    case modified, name
}

public enum LibraryError: LocalizedError {
    case invalidName(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name): "“\(name)” is not a valid file name."
        }
    }
}

/// File operations for the library sidebar: one root folder of Markdown and text notes.
public enum Library {
    public static let fileExtensions: Set<String> = ["md", "markdown", "txt"]
    public static let maxSearchFileSize = 5_000_000
    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey]

    /// The tree under `root`: notes, and the folders that contain notes at any depth. Folders first.
    /// Throws only if `root` itself can't be read; unreadable entries inside it are skipped.
    public static func scan(_ root: URL, sort: LibrarySort) throws -> [LibraryItem] {
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        var folders: [LibraryItem] = []
        var files: [LibraryItem] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            if values.isDirectory == true, values.isPackage != true {
                if let children = try? scan(url, sort: sort), !children.isEmpty {
                    folders.append(LibraryItem(url: url, name: url.lastPathComponent, isFolder: true, modified: modified, children: children))
                }
            } else if isNote(url) {
                files.append(LibraryItem(url: url, name: url.lastPathComponent, isFolder: false, modified: modified, children: nil))
            }
        }
        return sorted(folders, by: sort) + sorted(files, by: sort)
    }

    /// Notes whose name contains `query`, then notes whose text does (case- and diacritic-insensitive).
    /// Files larger than `maxSearchFileSize` are matched by name only. Reads every note: to search
    /// repeatedly, keep a `LibraryIndex`.
    public static func search(_ root: URL, query: String) -> [URL] {
        var index = LibraryIndex(root: root)
        index.refresh()
        return index.search(query)
    }

    /// Creates an empty `Untitled.md` (or `Untitled 2.md`, …) in `folder`, never overwriting.
    public static func createUntitled(in folder: URL) throws -> URL {
        var number = 1
        while true {
            let name = number == 1 ? "Untitled.md" : "Untitled \(number).md"
            let url = folder.appending(path: name)
            do {
                try Data().write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                number += 1
            }
        }
    }

    /// Renames in place; keeps the original extension when `newName` has none. Never replaces a file.
    public static func rename(_ url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.hasPrefix(".") else { throw LibraryError.invalidName(newName) }
        // "Meeting 2026.10.14" has the "extension" 14: keep the note's own extension unless the new
        // name ends in one the library recognises.
        let typed = (trimmed as NSString).pathExtension.lowercased()
        let name = fileExtensions.contains(typed) || url.pathExtension.isEmpty ? trimmed : "\(trimmed).\(url.pathExtension)"
        let destination = url.deletingLastPathComponent().appending(path: name)
        try FileManager.default.moveItem(at: url, to: destination)   // throws if the destination exists
        return destination
    }

    /// Moves `url` to the Trash and returns where it ended up.
    @discardableResult
    public static func trash(_ url: URL) throws -> URL? {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

    static func isNote(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }

    private static func sorted(_ items: [LibraryItem], by sort: LibrarySort) -> [LibraryItem] {
        switch sort {
        case .modified: items.sorted { $0.modified > $1.modified }
        case .name: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
