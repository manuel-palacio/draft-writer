import DraftKit
import Foundation
import Testing
@testable import Draft_Writer

@MainActor
@Suite struct LibraryStoreTests {
    let defaults: UserDefaults
    let folder: URL

    init() throws {
        defaults = UserDefaults(suiteName: "LibraryStoreTests-\(UUID().uuidString)")!
        folder = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "x".write(to: folder.appending(path: "a.md"), atomically: true, encoding: .utf8)
        try "An apple a day".write(to: folder.appending(path: "notes.md"), atomically: true, encoding: .utf8)
    }

    @Test func chooseScansFolder() async throws {
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        await store.refresh()
        #expect(Set(store.items.map(\.name)) == ["a.md", "notes.md"])
        #expect(store.root?.standardizedFileURL == folder.standardizedFileURL)
    }

    @Test func restoreAfterRelaunch() async throws {
        try LibraryStore(defaults: defaults).choose(folder)
        let relaunched = LibraryStore(defaults: defaults)
        relaunched.restore()
        #expect(relaunched.root?.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path)
    }

    @Test func staleBookmarkClearsRoot() throws {
        try LibraryStore(defaults: defaults).choose(folder)
        try FileManager.default.removeItem(at: folder)
        let relaunched = LibraryStore(defaults: defaults)
        relaunched.restore()
        #expect(relaunched.root == nil)
        #expect(defaults.data(forKey: LibraryStore.bookmarkKey) == nil)
    }

    @Test func queryRunsSearch() async throws {
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        store.query = "apple"
        await store.refresh()
        #expect(store.searchResults.map(\.lastPathComponent) == ["notes.md"])
    }

    @Test func newNoteGoesToRootOrFolder() async throws {
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        let note = try store.newNote(in: nil)
        #expect(note.lastPathComponent == "Untitled.md")
        #expect(FileManager.default.fileExists(atPath: note.path))
    }

    @Test func targetFolderFollowsSelection() throws {
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        store.selection = folder.appending(path: "a.md")
        #expect(store.targetFolder?.standardizedFileURL == folder.standardizedFileURL)
    }
}
