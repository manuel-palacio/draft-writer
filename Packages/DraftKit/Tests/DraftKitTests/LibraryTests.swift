import Foundation
import Testing
@testable import DraftKit

@Suite struct LibraryTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "library-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    @Test func scanFindsMarkdownAndTxt() throws {
        let now = Date()
        try file("a.md", modified: now.addingTimeInterval(-10))
        try file("b.txt", modified: now.addingTimeInterval(-20))
        try file("c.png")
        try file(".hidden.md")
        try file("sub/d.md")
        try FileManager.default.createDirectory(at: root.appending(path: "empty"), withIntermediateDirectories: true)
        let items = try Library.scan(root, sort: .modified)
        #expect(items.map(\.name) == ["sub", "a.md", "b.txt"])
        #expect(items.first?.children?.map(\.name) == ["d.md"])
        #expect(items.last?.children == nil)
    }

    @Test func sortByName() throws {
        for name in ["b.md", "A.md", "c.md"] { try file(name) }
        #expect(try Library.scan(root, sort: .name).map(\.name) == ["A.md", "b.md", "c.md"])
    }

    @Test func searchMatchesNameAndContent() throws {
        let byName = try file("apple.md", "x")
        let byContent = try file("notes.md", "An Apple a day")
        try file("other.md", "nothing")
        #expect(try Library.search(root, query: "apple").map(\.lastPathComponent) == [byName.lastPathComponent, byContent.lastPathComponent])
    }

    @Test func searchSkipsHugeFiles() throws {
        try file("huge.md", String(repeating: "x", count: Library.maxSearchFileSize + 1) + " needle")
        #expect(try Library.search(root, query: "needle").isEmpty)
    }

    @Test func untitledNumbering() throws {
        let names = try (0..<3).map { _ in try Library.createUntitled(in: root).lastPathComponent }
        #expect(names == ["Untitled.md", "Untitled 2.md", "Untitled 3.md"])
    }

    @Test func renameKeepsExtension() throws {
        let a = try file("a.md", "keep")
        let renamed = try Library.rename(a, to: "b")
        #expect(renamed.lastPathComponent == "b.md")
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "keep")
    }

    @Test func renameRefusesExisting() throws {
        let a = try file("a.md", "A")
        let b = try file("b.md", "B")
        #expect(throws: (any Error).self) { try Library.rename(a, to: "b") }
        #expect(try String(contentsOf: a, encoding: .utf8) == "A")
        #expect(try String(contentsOf: b, encoding: .utf8) == "B")
    }

    @Test func trashRemovesFromFolder() throws {
        let a = try file("a.md")
        try Library.trash(a)
        #expect(!FileManager.default.fileExists(atPath: a.path))
    }

    @Test func watcherFiresOnChange() async throws {
        let fired = AsyncStream<Void>.makeStream()
        let watcher = FolderWatcher(root, latency: 0.1) { fired.continuation.yield() }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        try file("new.md", "hello")
        let result = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in fired.stream { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(5)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(result)
    }
}
