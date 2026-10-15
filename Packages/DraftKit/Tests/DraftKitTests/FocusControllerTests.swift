import Foundation
import Testing
@testable import DraftKit

@Suite struct FocusControllerTests {
    let t = "First one. Second one.\n\nNew para here."

    func substring(_ range: NSRange?, of text: String) -> String? {
        range.map { (text as NSString).substring(with: $0) }
    }

    @Test func offReturnsNil() {
        #expect(FocusController.brightRange(in: t, selection: NSRange(location: 13, length: 0), mode: .off) == nil)
    }

    @Test func sentenceAtCursor() {
        let r = FocusController.brightRange(in: t, selection: NSRange(location: 13, length: 0), mode: .sentence)
        #expect(substring(r, of: t) == "Second one.")
    }

    @Test func paragraphAtCursor() {
        let r = FocusController.brightRange(in: t, selection: NSRange(location: 26, length: 0), mode: .paragraph)
        #expect(substring(r, of: t) == "New para here.")
    }

    @Test func selectionSpanningSentences() {
        let r = FocusController.brightRange(in: t, selection: NSRange(location: 3, length: 12), mode: .sentence)
        #expect(substring(r, of: t) == "First one. Second one.")
    }

    @Test func focusInEmptyText() {
        let r = FocusController.brightRange(in: "", selection: NSRange(location: 0, length: 0), mode: .sentence)
        #expect(r == NSRange(location: 0, length: 0))
    }

    @Test func focusAtEndOfText() {
        let r = FocusController.brightRange(in: t, selection: NSRange(location: t.utf16.count, length: 0), mode: .sentence)
        #expect(substring(r, of: t) == "New para here.")
    }

    @Test func cursorOnBlankLine() {
        let r = FocusController.brightRange(in: t, selection: NSRange(location: 23, length: 0), mode: .paragraph)
        #expect(r == NSRange(location: 23, length: 0))
    }

    @Test func modeCycles() {
        #expect(FocusMode.off.next == .sentence)
        #expect(FocusMode.sentence.next == .paragraph)
        #expect(FocusMode.paragraph.next == .off)
    }

    @Test func sentenceInJapanese() {
        let text = "今日は晴れです。明日は雨です。"
        let cursor = (text as NSString).range(of: "明日").location + 1
        let r = FocusController.brightRange(in: text, selection: NSRange(location: cursor, length: 0), mode: .sentence)
        #expect(substring(r, of: text) == "明日は雨です。")
    }

    @Test func sentenceWithEmoji() {
        let text = "Hi 👋🏽 there. Party time 🎉"
        let ns = text as NSString
        // Cursor between the two UTF-16 halves of the party emoji.
        let cursor = ns.range(of: "🎉").location + 1
        let r = FocusController.brightRange(in: text, selection: NSRange(location: cursor, length: 0), mode: .sentence)
        #expect(substring(r, of: text) == "Party time 🎉")
        let first = FocusController.brightRange(in: text, selection: NSRange(location: 4, length: 0), mode: .sentence)
        #expect(substring(first, of: text) == "Hi 👋🏽 there.")
    }

    @Test func paragraphEndingInEmoji() {
        let text = "One 🎉\n\nTwo"
        let r = FocusController.brightRange(in: text, selection: NSRange(location: 1, length: 0), mode: .paragraph)
        #expect(substring(r, of: text) == "One 🎉")
    }
}
