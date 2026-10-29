import Foundation
import Testing
@testable import DraftKit

@Suite struct MarkdownEditingTests {
    /// Applies `edit` to `text`, marking the resulting selection with `|` (caret) or `[` `]` (range).
    func apply(_ edit: TextEdit?, to text: String) -> String? {
        guard let edit else { return nil }
        let result = NSMutableString(string: text)
        result.replaceCharacters(in: edit.range, with: edit.replacement)
        if edit.selection.length == 0 {
            result.insert("|", at: edit.selection.location)
        } else {
            result.insert("]", at: NSMaxRange(edit.selection))
            result.insert("[", at: edit.selection.location)
        }
        return result as String
    }

    /// `text` with a `|` caret marker (or `[` `]` selection), split into the text and its selection.
    func parse(_ marked: String) -> (String, NSRange) {
        let ns = marked as NSString
        let caret = ns.range(of: "|")
        if caret.location != NSNotFound {
            return (ns.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
        }
        let open = ns.range(of: "["), close = ns.range(of: "]", options: .backwards)
        let text = (ns.replacingCharacters(in: close, with: "") as NSString).replacingCharacters(in: open, with: "")
        return (text, NSRange(location: open.location, length: close.location - open.location - 1))
    }

    // MARK: Wrapping

    @Test func wrapsSelection() {
        let (text, selection) = parse("a [word] b")
        #expect(apply(MarkdownEditing.wrap(text, selection: selection, marker: "**"), to: text) == "a **[word]** b")
    }

    @Test func insertsPairAroundCaret() {
        let (text, selection) = parse("a | b")
        #expect(apply(MarkdownEditing.wrap(text, selection: selection, marker: "*"), to: text) == "a *|* b")
    }

    @Test func linkWrapsSelectionAndPutsCaretInDestination() {
        let (text, selection) = parse("see [Draft] now")
        #expect(apply(MarkdownEditing.link(text, selection: selection), to: text) == "see [Draft](|) now")
    }

    @Test func linkWithoutSelectionPutsCaretInText() {
        let (text, selection) = parse("x |")
        #expect(apply(MarkdownEditing.link(text, selection: selection), to: text) == "x [|]()")
    }

    // MARK: Return

    func newline(_ marked: String) -> String? {
        let (text, selection) = parse(marked)
        return apply(MarkdownEditing.newline(text, at: selection.location), to: text)
    }

    @Test func continuesBulletLists() {
        #expect(newline("- one|") == "- one\n- |")
        #expect(newline("* one|") == "* one\n* |")
        #expect(newline("  + nested|") == "  + nested\n  + |")
    }

    @Test func continuesQuotesAndTasks() {
        #expect(newline("> quoted|") == "> quoted\n> |")
        #expect(newline("- [x] done|") == "- [x] done\n- [ ] |")
        #expect(newline("- [ ] todo|") == "- [ ] todo\n- [ ] |")
    }

    @Test func continuesOrderedListsAndRenumbers() {
        #expect(newline("1. one|") == "1. one\n2. |")
        #expect(newline("1. one|\n2. two\n   - child\n3. three\n\n1. other") == "1. one\n2. |\n3. two\n   - child\n4. three\n\n1. other")
        #expect(newline("9) nine|") == "9) nine\n10) |")
    }

    @Test func splitsAnItemAtTheCaret() {
        #expect(newline("- one|two") == "- one\n- |two")
    }

    @Test func returnOnEmptyItemEndsTheList() {
        #expect(newline("- one\n- |") == "- one\n|")
        #expect(newline("1. one\n2. |") == "1. one\n|")
        #expect(newline("> |") == "|")
        #expect(newline("- [ ] |") == "|")
    }

    @Test func plainLinesAreLeftToTheTextView() {
        #expect(newline("plain|") == nil)
        #expect(newline("|- one") == nil)       // caret before the marker
        #expect(newline("-not a list|") == nil)
    }

    // MARK: Indentation

    @Test func indentsAndOutdentsListItems() {
        let (text, selection) = parse("- one\n- tw|o")
        #expect(apply(MarkdownEditing.indent(text, selection: selection), to: text) == "- one\n    - tw|o")
        let (indented, caret) = parse("- one\n    - tw|o")
        #expect(apply(MarkdownEditing.outdent(indented, selection: caret), to: indented) == "- one\n- tw|o")
        let (tabbed, tabCaret) = parse("\t- tw|o")
        #expect(apply(MarkdownEditing.outdent(tabbed, selection: tabCaret), to: tabbed) == "- tw|o")
    }

    @Test func indentsEveryListLineInTheSelection() {
        let (text, selection) = parse("- [one\n- two]")
        #expect(apply(MarkdownEditing.indent(text, selection: selection), to: text) == "    - [one\n    - two]")
    }

    @Test func tabOutsideListsIsLeftToTheTextView() {
        let (text, selection) = parse("plain|")
        #expect(MarkdownEditing.indent(text, selection: selection) == nil)
        let (top, caret) = parse("- top|")
        #expect(MarkdownEditing.outdent(top, selection: caret) == nil)
    }

    // MARK: Tasks

    @Test func togglesTaskCheckboxes() {
        let (text, selection) = parse("- [ ] buy |milk")
        #expect(apply(MarkdownEditing.toggleTask(text, selection: selection), to: text) == "- [x] buy |milk")
        let (done, caret) = parse("  1. [X] d|one")
        #expect(apply(MarkdownEditing.toggleTask(done, selection: caret), to: done) == "  1. [ ] d|one")
        let (plain, plainCaret) = parse("- no box|")
        #expect(MarkdownEditing.toggleTask(plain, selection: plainCaret) == nil)
    }

    // MARK: Links under the pointer

    @Test func findsLinkDestinationAtLocation() {
        let text = "Intro.\n\nSee [the site](https://example.com) and <mailto:a@b.c> or https://bare.io/x."
        let ns = text as NSString
        #expect(MarkdownEditing.linkDestination(in: text, at: ns.range(of: "site").location) == "https://example.com")
        #expect(MarkdownEditing.linkDestination(in: text, at: ns.range(of: "example").location) == "https://example.com")
        #expect(MarkdownEditing.linkDestination(in: text, at: ns.range(of: "a@b").location) == "mailto:a@b.c")
        #expect(MarkdownEditing.linkDestination(in: text, at: ns.range(of: "bare").location) == "https://bare.io/x")
        #expect(MarkdownEditing.linkDestination(in: text, at: ns.range(of: "Intro").location) == nil)
        #expect(MarkdownEditing.linkDestination(in: text, at: ns.range(of: " and").location) == nil)
    }
}
