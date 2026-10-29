import AppKit
import Foundation
import Testing
@testable import DraftKit

/// Budgets from the spec: typing must stay smooth on a 50,000-word document.
/// Run in release mode: `swift test -c release --filter PerformanceTests`.
@Suite struct PerformanceTests {
    let text: String

    init() throws {
        let url = try #require(Bundle.module.url(forResource: "long", withExtension: "md", subdirectory: "Fixtures"))
        text = try String(contentsOf: url, encoding: .utf8)
    }

    func milliseconds(_ body: () -> Void) -> Double {
        let elapsed = ContinuousClock().measure(body)
        return Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
    }

    @Test func fixtureIsFiftyThousandWords() {
        #expect(TextStats.compute(text).words >= 50_000)
    }

    /// Runs off the main actor 300 ms after each edit; the footer should catch up well within a second.
    @Test func statsLongDocument() {
        let bridged = NSTextStorage(string: text).string
        let ms = milliseconds { _ = TextStats.compute(bridged) }
        #expect(ms < 300, "stats took \(ms) ms")
        print("stats: \(ms) ms")
    }

    @Test func stylesLongDocument() {
        _ = MarkdownStyler.styles(for: text)   // warm up
        let ms = milliseconds { _ = MarkdownStyler.styles(for: text) }
        #expect(ms < 150, "styling took \(ms) ms")
    }

    /// Text read back from NSTextView is a bridged, UTF-16-backed String; it must be just as fast.
    @Test func stylesBridgedLongDocument() {
        let bridged = NSTextStorage(string: text).string
        let ms = milliseconds { _ = MarkdownStyler.styles(for: bridged) }
        #expect(ms < 150, "styling a bridged string took \(ms) ms")
    }

    /// Runs on every save of a document.
    @Test func lineEndingsOnLongDocument() {
        let bridged = NSTextStorage(string: text).string
        let ms = milliseconds { _ = LineEnding.crlf.apply(to: bridged) }
        #expect(ms < 100, "normalising line endings took \(ms) ms")
    }

    /// Autosave of a very large note (about 1.5 million words) must not stall.
    @Test func lineEndingsOnHugeDocument() {
        let huge = NSTextStorage(string: String(repeating: text + "\r\n", count: 30)).string
        let lf = NSTextStorage(string: String(repeating: text + "\n", count: 30)).string
        let ms = milliseconds { _ = LineEnding.crlf.apply(to: huge) }
        #expect(ms < 200, "CRLF normalising took \(ms) ms")
        let lfMs = milliseconds { _ = LineEnding.lf.apply(to: lf) }
        #expect(lfMs < 50, "LF fast path took \(lfMs) ms")
    }

    /// Typing in the library search box: a query over 2,000 notes of a few KB each, on a warm index.
    @Test func searchTwoThousandNotes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "perf-library-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let words = text.split(separator: " ")
        for number in 0..<2_000 {
            let start = (number * 500) % (words.count - 500)
            let note = words[start..<start + 500].joined(separator: " ")   // about 3 KB
            try note.write(to: root.appending(path: "Note \(number).md"), atomically: false, encoding: .utf8)
        }
        var index = LibraryIndex(root: root)
        index.refresh()
        let refreshMs = milliseconds { index.refresh() }
        let ms = milliseconds { _ = index.search("Zürich harbour") }
        #expect(ms < 50, "searching 2,000 notes took \(ms) ms")
        #expect(refreshMs < 50, "refreshing an unchanged index of 2,000 notes took \(refreshMs) ms")
        print("library search: query \(ms) ms, unchanged refresh \(refreshMs) ms")
    }

    @Test func focusLongDocument() {
        let middle = NSRange(location: (text as NSString).length / 2, length: 0)
        let ms = milliseconds { _ = FocusController.brightRange(in: text, selection: middle, mode: .sentence) }
        #expect(ms < 5, "focus took \(ms) ms")
    }
}
