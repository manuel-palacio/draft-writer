import DraftKit
import Foundation
import Observation

/// The library sidebar's state, shared by all windows: the chosen root folder (kept across launches as a
/// security-scoped bookmark), its note tree, and search results. File work runs off the main actor.
@MainActor @Observable
final class LibraryStore {
    static let shared = LibraryStore(defaults: .standard)
    static let bookmarkKey = "libraryBookmark"

    private(set) var root: URL?
    private(set) var items: [LibraryItem] = []
    private(set) var searchResults: [URL] = []
    var sort: LibrarySort {
        didSet {
            defaults.set(sort.rawValue, forKey: "librarySort")
            Task { await refresh() }
        }
    }
    var query = "" { didSet { if query != oldValue { Task { await refresh() } } } }
    /// The row selected in the sidebar (a note or a folder).
    var selection: URL?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var accessedURL: URL?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        sort = defaults.string(forKey: "librarySort").flatMap(LibrarySort.init) ?? .modified
    }

    /// Where a new note goes: the selected folder, the selected note's folder, or the root.
    var targetFolder: URL? {
        guard let selection else { return root }
        return selection.hasDirectoryPath || (try? selection.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            ? selection : selection.deletingLastPathComponent()
    }

    func choose(_ folder: URL) throws {
        let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        activate(folder)
    }

    /// Re-opens the saved folder. A bookmark that no longer resolves to an existing folder is forgotten,
    /// so the sidebar shows "Choose Folder…" again.
    func restore() {
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path) else {
            defaults.removeObject(forKey: Self.bookmarkKey)
            deactivate()
            return
        }
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        activate(url)
    }

    func refresh() async {
        guard let root else { return }
        let sort = sort
        let query = query
        if query.isEmpty {
            let scanned = await Task.detached { (try? Library.scan(root, sort: sort)) ?? [] }.value
            items = scanned
            searchResults = []
        } else {
            let found = await Task.detached { (try? Library.search(root, query: query)) ?? [] }.value
            if query == self.query { searchResults = found }
        }
    }

    func newNote(in folder: URL?) throws -> URL {
        guard let target = folder ?? root else { throw CocoaError(.fileNoSuchFile) }
        let url = try Library.createUntitled(in: target)
        Task { await refresh() }
        return url
    }

    func rename(_ url: URL, to name: String) throws {
        let renamed = try Library.rename(url, to: name)
        if selection == url { selection = renamed }
        Task { await refresh() }
    }

    func trash(_ url: URL) throws {
        try Library.trash(url)
        if selection == url { selection = nil }
        Task { await refresh() }
    }

    private func activate(_ url: URL) {
        deactivate()
        if url.startAccessingSecurityScopedResource() { accessedURL = url }
        root = url
        watcher = FolderWatcher(url) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    private func deactivate() {
        watcher?.stop()
        watcher = nil
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        root = nil
        items = []
        searchResults = []
    }
}
