import class AppKit.NSDocumentController
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
    /// Every `#tag` in the library's notes, lowercased and sorted.
    private(set) var tags: [String] = []
    var sort: LibrarySort {
        didSet {
            defaults.set(sort.rawValue, forKey: "librarySort")
            Task { await refresh() }
        }
    }
    /// Search text. Searching starts 200 ms after the last keystroke.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            queryTask?.cancel()
            queryTask = Task { [weak self] in
                try? await Task.sleep(for: Self.queryDelay)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }
    /// The row selected in the sidebar (a note or a folder).
    var selection: URL?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watcher: FolderWatcher?
    /// The notes' searchable text, refreshed whenever the watcher reports a change.
    @ObservationIgnored private var index: LibraryIndex?
    /// Security scopes opened this session. Never closed while the app runs: notes opened from a
    /// library folder save through its scope, even after another folder is chosen.
    @ObservationIgnored private(set) var activeScopes: [URL] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    static let queryDelay: Duration = .milliseconds(200)

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
        // Activate through the bookmark, so the security scope is one this process can keep open.
        var isStale = false
        let scoped = (try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                               bookmarkDataIsStale: &isStale)) ?? folder
        activate(scoped)
    }

    /// Re-opens the saved folder. A bookmark that no longer resolves to an existing folder is forgotten,
    /// so the sidebar shows "Choose Folder…" again.
    func restore() {
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &isStale),
              Self.isUsable(url) else {
            forget()
            return
        }
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        activate(url)
    }

    /// Rescans (or searches) the library. A newer refresh cancels an older one, and results are applied only
    /// if the root, sort and query they were made for are still current. A root that was deleted or moved
    /// to the Trash is forgotten, which brings back the "Choose Folder…" prompt.
    func refresh() async {
        refreshTask?.cancel()
        var current = Task { await performRefresh() }
        refreshTask = current
        await current.value
        // If a newer refresh superseded this one, wait for that, so callers always see fresh state.
        while let latest = refreshTask, latest != current {
            current = latest
            await current.value
        }
    }

    private func performRefresh() async {
        guard let root else { return }
        guard Self.isUsable(root) else {
            forget()
            return
        }
        let sort = sort
        let query = query
        if query.isEmpty {
            let scanned = await Task.detached { (try? Library.scan(root, sort: sort)) ?? [] }.value
            guard !Task.isCancelled, root == self.root, sort == self.sort, self.query.isEmpty else { return }
            items = scanned
            searchResults = []
            await refreshIndex()   // warm it, so the first query doesn't read every note
        } else {
            await refreshIndex()
            let index = index
            let found = await Task.detached { index?.results(for: query) ?? [] }.value
            guard !Task.isCancelled, root == self.root, query == self.query else { return }
            searchResults = found
        }
    }

    /// Re-reads only the notes that changed on disk since the last refresh.
    private func refreshIndex() async {
        guard let index else { return }
        let refreshed = await Task.detached {
            var index = index
            index.refresh()
            return index
        }.value
        // Only the newest refresh may store its index: an older one could undo a change a newer one saw.
        guard !Task.isCancelled, refreshed.root == root else { return }
        self.index = refreshed
        let tags = refreshed.tags
        if tags != self.tags { self.tags = tags }
    }

    /// A library root must exist and must not be in the Trash (Finder "deletes" folders by moving them there,
    /// and the bookmark follows).
    static func isUsable(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var relationship = FileManager.URLRelationship.other
        try? FileManager.default.getRelationship(&relationship, of: .trashDirectory, in: .userDomainMask, toItemAt: url)
        return relationship != .contains && !url.resolvingSymlinksInPath().pathComponents.contains(".Trash")
    }

    /// The library note a `[[name]]` link points to.
    func note(named name: String) -> URL? {
        Library.note(named: name, in: Library.notes(in: items).map(\.url))
    }

    /// Creates `<name>.md` in the target folder, for a `[[name]]` link to a note that doesn't exist yet.
    func createNote(named name: String) throws -> URL {
        guard let target = targetFolder else { throw CocoaError(.fileNoSuchFile) }
        let url = try Library.createNote(named: name, in: target)
        Task { await refresh() }
        return url
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

    /// Moves a note or folder to the Trash and closes the windows of the notes it held (they would
    /// otherwise keep editing files in the Trash). Unsaved edits are saved first, so they go to the Trash
    /// with the file. Returns where the item ended up.
    @discardableResult
    func trash(_ url: URL) async throws -> URL? {
        let path = url.resolvingSymlinksInPath().path
        let open = NSDocumentController.shared.documents.filter { document in
            guard let file = document.fileURL?.resolvingSymlinksInPath().path else { return false }
            return file == path || file.hasPrefix(path + "/")
        }
        for document in open where document.isDocumentEdited {
            try await document.autosave(withImplicitCancellability: false)
        }
        let trashed = try Library.trash(url)
        open.forEach { $0.close() }
        if selection == url { selection = nil }
        Task { await refresh() }
        return trashed
    }

    #if DEBUG
    /// UI tests: writes `notes` (relative path → text) to a fresh folder in the app's own temporary directory and
    /// browses it for this launch, without replacing the saved library. The test runner can't write into the
    /// sandboxed app's container itself.
    func activateFixtureForTesting(_ notes: [String: String]) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ui-library-\(UUID().uuidString)", directoryHint: .isDirectory)
        for (path, text) in notes {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        activate(folder)
    }
    #endif

    private func activate(_ url: URL) {
        deactivate()
        if !activeScopes.contains(url), url.startAccessingSecurityScopedResource() { activeScopes.append(url) }
        root = url
        index = LibraryIndex(root: url)
        watcher = FolderWatcher(url) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    /// Drops the saved folder: the sidebar shows "Choose Folder…" again.
    private func forget() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        deactivate()
    }

    private func deactivate() {
        watcher?.stop()
        watcher = nil
        index = nil
        root = nil
        items = []
        searchResults = []
        selection = nil
    }
}
