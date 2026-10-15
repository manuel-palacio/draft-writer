import AppKit
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

    @Test func trashClosesTheNotesWindow() async throws {
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        let note = folder.appending(path: "a.md")
        let document = NSDocument()
        document.fileURL = note
        NSDocumentController.shared.addDocument(document)
        defer { NSDocumentController.shared.removeDocument(document) }
        try await store.trash(note)
        #expect(!NSDocumentController.shared.documents.contains(document))
    }

    /// A document with unsaved typing, saved in place like Draft Writer's (autosave in place).
    final class EditedDocument: NSDocument {
        var text = "typed since the last autosave"
        override class var autosavesInPlace: Bool { true }
        override func data(ofType typeName: String) throws -> Data { Data(text.utf8) }
    }

    @Test func trashSavesUnsavedEditsFirst() async throws {
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        let note = folder.appending(path: "a.md")
        let document = EditedDocument()
        document.fileURL = note
        document.fileType = "net.daringfireball.markdown"
        document.updateChangeCount(.changeDone)
        NSDocumentController.shared.addDocument(document)
        defer { NSDocumentController.shared.removeDocument(document) }
        let trashed = try await store.trash(note)
        let saved = try String(contentsOf: try #require(trashed), encoding: .utf8)
        #expect(saved == "typed since the last autosave")   // the edits went into the file before it moved
    }

    @Test func newNoteCommandReportsErrors() async throws {
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        store.selection = folder.appending(path: "gone", directoryHint: .isDirectory)   // a folder that no longer exists
        var reported: (any Error)?
        var opened: URL?
        await LibraryCommands.newNote(store: store, open: { opened = $0 }, report: { reported = $0 })
        #expect(reported != nil)
        #expect(opened == nil)
    }

    @Test func newNoteCommandOpensTheNote() async throws {
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        var opened: URL?
        await LibraryCommands.newNote(store: store, open: { opened = $0 }, report: { _ in })
        #expect(opened?.lastPathComponent == "Untitled.md")
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

    @Test func trashedFolderIsForgottenOnRelaunch() throws {
        try LibraryStore(defaults: defaults).choose(folder)
        try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        let relaunched = LibraryStore(defaults: defaults)
        relaunched.restore()
        #expect(relaunched.root == nil)
        #expect(defaults.data(forKey: LibraryStore.bookmarkKey) == nil)
    }

    @Test func folderTrashedWhileRunningShowsPrompt() async throws {
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        await store.refresh()
        try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        await store.refresh()
        #expect(store.root == nil)
        #expect(store.items.isEmpty)
    }

    @Test func switchingFoldersKeepsEarlierAccess() throws {
        let other = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        try store.choose(other)
        // notes opened from the first folder still save: its security scope stays active this session
        #expect(store.activeScopes.map(\.standardizedFileURL).contains(folder.standardizedFileURL))
    }

    @Test func clearingQueryShowsTreeNotStaleResults() async throws {
        let store = LibraryStore(defaults: defaults)
        try store.choose(folder)
        store.query = "apple"
        store.query = ""
        await store.refresh()
        #expect(store.searchResults.isEmpty)
        #expect(store.items.count == 2)
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
