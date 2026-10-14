import AppKit

/// The editing surface: a TextKit 2 `NSTextView` that keeps its text in a centred column.
final class DraftTextView: NSTextView {
    var columnWidth = 70 { didSet { updateInsets() } }

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

    private func updateInsets() {
        let horizontal = Theme.columnInset(viewWidth: frame.width, font: baseFont, columns: columnWidth)
        let inset = NSSize(width: horizontal, height: 40)
        if textContainerInset != inset { textContainerInset = inset }
    }
}
