import AppKit
import DraftKit
import SwiftUI
import Testing
@testable import Draft_Writer

/// Drives the real editor in an offscreen window: typing goes through NSTextView's input path,
/// so undo, delegate callbacks and styling run exactly as they do for a user.
@MainActor
final class EditorHarness {
    var text = ""
    var selection = NSRange(location: 0, length: 0)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let coordinator: EditorView.Coordinator
    let textView: DraftTextView

    init(initial: String = "") {
        text = initial
        var view: EditorView!
        let box = Box()
        view = EditorView(text: Binding(get: { box.harness?.text ?? initial }, set: { box.harness?.text = $0 }),
                          selection: Binding(get: { box.harness?.selection ?? NSRange() }, set: { box.harness?.selection = $0 }),
                          font: Theme.font(.duo, size: 17), columnWidth: 70)
        coordinator = view.makeCoordinator()
        let (scrollView, textView) = DraftTextView.make()
        textView.delegate = coordinator
        textView.string = initial
        coordinator.textView = textView
        self.textView = textView
        window.contentView = scrollView
        box.harness = self
        coordinator.restyleAll()
    }

    func type(_ string: String) {
        window.makeFirstResponder(textView)
        textView.insertText(string, replacementRange: textView.selectedRange())
    }

    func font(at location: Int) -> NSFont? {
        textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    func color(at location: Int) -> NSColor? {
        textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    final class Box { weak var harness: EditorHarness? }
}

@MainActor
@Suite struct EditorViewTests {
    @Test func typingUpdatesBindingAndStylesHeading() {
        let h = EditorHarness()
        h.type("# Hello *world*")
        #expect(h.text == "# Hello *world*")
        #expect(h.font(at: 2)?.fontName == "iAWriterDuoS-Bold")      // heading text is bold
        #expect(h.color(at: 0) == Theme.marker)                       // "#" greyed
        #expect(h.font(at: 9)?.fontName == "iAWriterDuoS-BoldItalic") // *world* inside a heading
    }

    @Test func stylingAddsNoUndoSteps() throws {
        let h = EditorHarness()
        h.type("**bold**")
        h.coordinator.restyleAll()
        let undo = try #require(h.textView.undoManager)
        undo.undo()
        #expect(h.textView.string == "")
        #expect(!undo.canUndo)
    }

    @Test func markedTextCompositionCompletes() {
        let h = EditorHarness(initial: "*")
        h.window.makeFirstResponder(h.textView)
        h.textView.setSelectedRange(NSRange(location: 1, length: 0))
        h.textView.setMarkedText("¨", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(h.textView.hasMarkedText())
        h.textView.insertText("ä", replacementRange: h.textView.markedRange())
        h.type("*")
        #expect(h.text == "*ä*")
        #expect(h.font(at: 1)?.fontName == "iAWriterDuoS-Italic")
    }

    @Test func externalChangeReplacesText() {
        let h = EditorHarness(initial: "old")
        h.textView.string = "new *text*"
        h.coordinator.restyleAll()
        #expect(h.font(at: 5)?.fontName == "iAWriterDuoS-Italic")
    }
}
