import AppKit
import DraftKit

/// The editing surface: a TextKit 2 `NSTextView` that keeps its text in a centred column.
final class DraftTextView: NSTextView {
    var columnWidth = 70 { didSet { updateInsets() } }
    var typewriter = false {
        didSet {
            updateInsets()
            centerCaret()
        }
    }

    var baseFont: NSFont = Theme.font(.duo, size: 17) {
        didSet {
            font = baseFont
            typingAttributes = Self.baseAttributes(font: baseFont)
            updateInsets()
        }
    }

    static func make() -> (NSScrollView, DraftTextView) {
        let textView = DraftTextView(usingTextLayoutManager: true)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = Theme.link
        textView.textColor = Theme.text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.baseFont = Theme.font(.duo, size: 17)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.background
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    static func baseAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Theme.lineHeightMultiple
        return [.font: font, .foregroundColor: Theme.text, .paragraphStyle: paragraph]
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    override func viewWillDraw() {
        updateInsets()   // the visible height changes when the window is resized
        super.viewWillDraw()
    }

    /// Typewriter scrolling: keep the caret line in the vertical middle of the window.
    /// True while a click or drag is selecting text: typewriter mode then leaves the scroll position alone,
    /// so the text doesn't move under the pointer. It re-centres on the next keystroke.
    private(set) var isMouseSelecting = false

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), openLink(at: characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))) {
            return
        }
        isMouseSelecting = true
        defer { isMouseSelecting = false }
        super.mouseDown(with: event)   // tracks the mouse until it goes up
    }

    // MARK: Markdown editing

    /// Opens web and mail links in their default apps (replaceable in tests).
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// Opens a `[[Note]]` by name (set by the window, which knows the library).
    var openWikilink: ((String) -> Void)?

    /// ⌘-click: opens the wikilink, or the http(s) or mailto link, at `location`. Returns false (a normal click)
    /// if there is none.
    func openLink(at location: Int) -> Bool {
        if let openWikilink, let name = NoteLinks.wikilink(in: string, at: location) {
            openWikilink(name)
            return true
        }
        guard let destination = MarkdownEditing.linkDestination(in: string, at: location),
              let url = URL(string: destination), PreviewView.Coordinator.opensExternally(url) else { return false }
        openURL(url)
        return true
    }

    @objc func formatBold(_ sender: Any?) { apply(MarkdownEditing.wrap(string, selection: selectedRange(), marker: "**")) }
    @objc func formatItalic(_ sender: Any?) { apply(MarkdownEditing.wrap(string, selection: selectedRange(), marker: "*")) }
    @objc func formatLink(_ sender: Any?) { apply(MarkdownEditing.link(string, selection: selectedRange())) }

    @objc func toggleTaskCheckbox(_ sender: Any?) {
        if let edit = MarkdownEditing.toggleTask(string, selection: selectedRange()) { apply(edit) }
    }

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard !hasMarkedText(), selection.length == 0,
              let edit = MarkdownEditing.newline(string, at: selection.location) else { return super.insertNewline(sender) }
        apply(edit)
    }

    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText(), let edit = MarkdownEditing.indent(string, selection: selectedRange()) else { return super.insertTab(sender) }
        apply(edit)
    }

    override func insertBacktab(_ sender: Any?) {
        guard !hasMarkedText(), let edit = MarkdownEditing.outdent(string, selection: selectedRange()) else { return super.insertBacktab(sender) }
        apply(edit)
    }

    /// Makes `edit` as one undo step, through the same path as typing (so the delegate restyles and the document
    /// sees the change).
    func apply(_ edit: TextEdit) {
        breakUndoCoalescing()
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: typingAttributes))
        didChangeText()
        setSelectedRange(edit.selection)
        breakUndoCoalescing()
    }

    /// Scrolls so the caret's line sits in the middle of the view. The caret rect comes from TextKit 2's
    /// text segments (container coordinates), which works whether or not the window is on screen.
    func centerCaret() {
        guard typewriter, !isMouseSelecting, let scrollView = enclosingScrollView, let tlm = textLayoutManager,
              let caret = tlm.location(tlm.documentRange.location, offsetBy: selectedRange().location) else { return }
        tlm.ensureLayout(for: NSTextRange(location: caret))
        var caretRect: CGRect?
        tlm.enumerateTextSegments(in: NSTextRange(location: caret), type: .standard, options: []) { _, rect, _, _ in
            caretRect = rect
            return false
        }
        guard let caretRect else { return }
        let midY = caretRect.midY + textContainerOrigin.y
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: max(0, midY - clip.bounds.height / 2)))
        scrollView.reflectScrolledClipView(clip)
    }

    private func updateInsets() {
        let horizontal = Theme.columnInset(viewWidth: frame.width, font: baseFont, columns: columnWidth)
        let vertical = typewriter ? ((enclosingScrollView?.contentSize.height ?? 0) / 2).rounded() : 40
        let inset = NSSize(width: horizontal, height: vertical)
        if textContainerInset != inset { textContainerInset = inset }
    }
}
