import Foundation
import Testing
@testable import DraftKit

@Suite struct LibraryIndexTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "index-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ path: String, _ content: String = "", modified: Date? = nil) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    func indexed() -> LibraryIndex {
        var index = LibraryIndex(root: root)
        index.refresh()
        return index
    }

    @Test func nameMatchesComeFirstThenContentEachSortedByPath() throws {
        try file("b/apple pie.md", "x")
        try file("Apple 10.md", "x")
        try file("Apple 9.md", "x")
        try file("y.md", "an apple")
        try file("a/zz.txt", "APPLE")
        try file("other.md", "nothing")
        // By path, not by name: "b/apple pie.md" sorts after "Apple 10.md", and "a/zz.txt" before "y.md".
        #expect(indexed().search("apple").map(\.lastPathComponent) == ["Apple 9.md", "Apple 10.md", "apple pie.md", "zz.txt", "y.md"])
    }

    @Test func caseAndDiacriticInsensitive() throws {
        try file("Café.md", "x")
        try file("notes.md", "a CRÈME brûlée")
        let index = indexed()
        #expect(index.search("cafe").map(\.lastPathComponent) == ["Café.md"])
        #expect(index.search("creme BRULEE").map(\.lastPathComponent) == ["notes.md"])
        #expect(index.search("  café  ").map(\.lastPathComponent) == ["Café.md"])
    }

    @Test func collectsTagsAndFindsTaggedNotes() throws {
        try file("b.md", "Plan #Work and #ideas")
        try file("a.md", "#work only")
        try file("c.md", "`#code` is not a tag")
        var index = indexed()
        #expect(index.tags == ["ideas", "work"])
        #expect(index.notes(taggedWith: "WORK").map(\.lastPathComponent) == ["a.md", "b.md"])
        try file("c.md", "now #work too", modified: Date().addingTimeInterval(10))
        index.refresh()
        #expect(index.notes(taggedWith: "work").map(\.lastPathComponent) == ["a.md", "b.md", "c.md"])
        #expect(index.results(for: "#ideas").map(\.lastPathComponent) == ["b.md"])
        #expect(index.results(for: "plan").map(\.lastPathComponent) == ["b.md"])
    }

    @Test func emptyQueryFindsNothing() throws {
        try file("a.md", "x")
        #expect(indexed().search(" ").isEmpty)
    }

    @Test func skipsHiddenNonNotesPackagesAndHugeContent() throws {
        try file(".hidden.md", "needle")
        try file("image.png", "needle")
        try file("Tool.app/text.md", "needle")
        try file("huge.md", String(repeating: "x", count: Library.maxSearchFileSize + 1) + " needle")
        try file("needle huge.md", String(repeating: "x", count: Library.maxSearchFileSize + 1))
        #expect(indexed().search("needle").map(\.lastPathComponent) == ["needle huge.md"])
    }

    @Test func refreshPicksUpAddedChangedAndDeletedNotes() throws {
        let old = Date().addingTimeInterval(-60)
        try file("changed.md", "before", modified: old)
        let deleted = try file("deleted.md", "word", modified: old)
        var index = indexed()
        #expect(index.search("word").map(\.lastPathComponent) == ["deleted.md"])

        try file("changed.md", "now a word")
        try file("added.md", "word too")
        try FileManager.default.removeItem(at: deleted)
        index.refresh()

        #expect(index.search("word").map(\.lastPathComponent) == ["added.md", "changed.md"])
        #expect(index.search("before").isEmpty)
    }

    @Test func refreshKeepsUnchangedNotesWithoutRereading() throws {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try file("note.md", "original", modified: date)
        var index = indexed()
        // Same size and date: the index can't tell, so it keeps the text it already has.
        try file("note.md", "replaced", modified: date)
        index.refresh()
        #expect(index.search("original").map(\.lastPathComponent) == ["note.md"])
    }
}
