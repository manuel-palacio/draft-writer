import AppKit
import Testing
@testable import Draft_Writer

/// The Markdown editing commands, driven through the real text view: each is one undo step.
@MainActor
@Suite struct MarkdownEditingViewTests {
    func harness(_ text: String, selection: NSRange) -> EditorHarness {
        let h = EditorHarness(initial: text)
        h.window.makeFirstResponder(h.textView)
        h.textView.setSelectedRange(selection)
        h.textView.undoManager?.groupsByEvent = false
        return h
    }

    /// AppKit groups undo steps per event (keystroke, menu command); tests have no events, so group explicitly.
    func event(_ h: EditorHarness, _ body: () -> Void) {
        h.textView.undoManager?.beginUndoGrouping()
        body()
        h.textView.undoManager?.endUndoGrouping()
    }

    func undoOnce(_ h: EditorHarness) throws {
        try #require(h.textView.undoManager).undo()
    }

    @Test func boldWrapsSelectionAsOneUndoStep() throws {
        let h = harness("a word", selection: NSRange(location: 2, length: 0))
        event(h) { h.type("!") }   // typing just before must not merge into the same undo step
        h.textView.setSelectedRange(NSRange(location: 2, length: 1))
        event(h) { h.textView.formatBold(nil) }
        #expect(h.text == "a **!**word")
        #expect(h.textView.selectedRange() == NSRange(location: 4, length: 1))
        try undoOnce(h)
        #expect(h.textView.string == "a !word")
    }

    @Test func italicAndLinkInsertAtCaret() {
        let h = harness("x ", selection: NSRange(location: 2, length: 0))
        event(h) { h.textView.formatItalic(nil) }
        #expect(h.text == "x **")
        #expect(h.textView.selectedRange() == NSRange(location: 3, length: 0))
        let link = harness("see Draft", selection: NSRange(location: 4, length: 5))
        event(link) { link.textView.formatLink(nil) }
        #expect(link.text == "see [Draft]()")
        #expect(link.textView.selectedRange() == NSRange(location: 12, length: 0))
    }

    @Test func returnContinuesAndRenumbersLists() throws {
        let h = harness("1. one\n2. two", selection: NSRange(location: 6, length: 0))
        event(h) { h.textView.insertNewline(nil) }
        #expect(h.text == "1. one\n2. \n3. two")
        #expect(h.textView.selectedRange() == NSRange(location: 10, length: 0))
        try undoOnce(h)
        #expect(h.textView.string == "1. one\n2. two")
    }

    @Test func returnOnEmptyItemEndsTheList() {
        let h = harness("- one\n- ", selection: NSRange(location: 8, length: 0))
        event(h) { h.textView.insertNewline(nil) }
        #expect(h.text == "- one\n")
    }

    @Test func returnOutsideListsIsAPlainNewline() {
        let h = harness("plain", selection: NSRange(location: 5, length: 0))
        event(h) { h.textView.insertNewline(nil) }
        #expect(h.text == "plain\n")
    }

    @Test func tabAndShiftTabIndentListItems() throws {
        let h = harness("- one\n- two", selection: NSRange(location: 10, length: 0))
        event(h) { h.textView.insertTab(nil) }
        #expect(h.text == "- one\n    - two")
        #expect(h.textView.selectedRange() == NSRange(location: 14, length: 0))
        event(h) { h.textView.insertBacktab(nil) }
        #expect(h.text == "- one\n- two")
        let plain = harness("plain", selection: NSRange(location: 5, length: 0))
        event(plain) { plain.textView.insertTab(nil) }
        #expect(plain.text == "plain\t")
    }

    @Test func toggleTaskSwitchesTheCheckbox() throws {
        let h = harness("- [ ] milk", selection: NSRange(location: 8, length: 0))
        event(h) { h.textView.toggleTaskCheckbox(nil) }
        #expect(h.text == "- [x] milk")
        event(h) { h.textView.toggleTaskCheckbox(nil) }
        #expect(h.text == "- [ ] milk")
        try undoOnce(h)
        #expect(h.textView.string == "- [x] milk")
    }

    @Test func commandClickOpensWebAndMailLinksOnly() {
        let text = "[site](https://example.com) [mail](mailto:a@b.c) [doc](other.md) plain"
        let h = harness(text, selection: NSRange(location: 0, length: 0))
        var opened: [URL] = []
        h.textView.openURL = { opened.append($0) }
        let ns = text as NSString
        #expect(h.textView.openLink(at: ns.range(of: "site").location))
        #expect(h.textView.openLink(at: ns.range(of: "mail]").location))
        #expect(!h.textView.openLink(at: ns.range(of: "doc").location))
        #expect(!h.textView.openLink(at: ns.range(of: "plain").location))
        #expect(opened == [URL(string: "https://example.com")!, URL(string: "mailto:a@b.c")!])
    }

    @Test func commandClickOnAWikilinkOpensTheNoteByName() {
        let text = "See [[Other Note]] and [site](https://example.com)"
        let h = harness(text, selection: NSRange(location: 0, length: 0))
        var names: [String] = []
        var opened: [URL] = []
        h.textView.openWikilink = { names.append($0) }
        h.textView.openURL = { opened.append($0) }
        let ns = text as NSString
        #expect(h.textView.openLink(at: ns.range(of: "Other").location))
        #expect(h.textView.openLink(at: ns.range(of: "site").location))
        #expect(names == ["Other Note"])
        #expect(opened == [URL(string: "https://example.com")!])
    }

    @Test func commandClickEventOpensTheLinkUnderThePointer() throws {
        let h = harness("[site](https://example.com)", selection: NSRange(location: 0, length: 0))
        h.window.layoutIfNeeded()
        var opened: [URL] = []
        h.textView.openURL = { opened.append($0) }
        // A point on the first line, a few characters in (window coordinates, bottom-left origin).
        let origin = h.textView.convert(h.textView.textContainerOrigin, to: nil)
        let point = NSPoint(x: origin.x + 20, y: origin.y - 10)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: .command,
                                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: h.window.windowNumber, context: nil,
                                                    eventNumber: 0, clickCount: 1, pressure: 1))
        h.textView.mouseDown(with: click)
        #expect(opened == [URL(string: "https://example.com")!])
    }
}
