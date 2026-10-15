import AppKit

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
        isMouseSelecting = true
        defer { isMouseSelecting = false }
        super.mouseDown(with: event)   // tracks the mouse until it goes up
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
