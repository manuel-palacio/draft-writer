import AppKit
import DraftKit
import NaturalLanguage
import SwiftUI

/// Hosts `DraftTextView` in SwiftUI and keeps it in sync with the document text.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var font: NSFont
    var columnWidth: Int
    var focusMode: FocusMode = .off
    /// Part-of-speech classes to colour; empty turns highlighting off.
    var highlightClasses: Set<LexicalClass> = []
    var typewriter = false
    /// Called with the 1-based source line at the top of the visible area when the editor scrolls.
    var onTopLineChange: ((Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = DraftTextView.make()
        textView.delegate = context.coordinator
        textView.baseFont = font
        textView.columnWidth = columnWidth
        textView.string = text
        textView.typewriter = typewriter
        context.coordinator.textView = textView
        context.coordinator.observeScrolling(of: scrollView)
        context.coordinator.restyleAll()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        var needsRestyle = false
        if textView.baseFont != font {
            textView.baseFont = font
            needsRestyle = true
        }
        if textView.columnWidth != columnWidth { textView.columnWidth = columnWidth }
        if textView.typewriter != typewriter { textView.typewriter = typewriter }
        let focusChanged = coordinator.appliedFocusMode != focusMode || coordinator.appliedHighlightClasses != highlightClasses
        if textView.string != text {
            // External change (revert, undo through the document): replace and keep the caret in range.
            let caret = min(textView.selectedRange().location, (text as NSString).length)
            textView.string = text
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            needsRestyle = true
        }
        if needsRestyle { coordinator.restyleAll() }
        if focusChanged || needsRestyle { coordinator.applyFocus() }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        static let restyleDelay: Duration = .milliseconds(150)

        var parent: EditorView
        weak var textView: DraftTextView?
        private var pendingRestyle: Task<Void, Never>?
        private var lastEditedRange: NSRange?
        private(set) var appliedFocusMode: FocusMode = .off
        /// Fenced code blocks from the last full pass, shifted as text is edited, so the fast path
        /// can re-parse a whole block instead of a fragment that loses its fences.
        private var codeBlocks: [NSRange] = []
        /// Inline code and code blocks from the last full pass; never highlighted.
        private var codeRanges: [NSRange] = []
        private(set) var appliedHighlightClasses: Set<LexicalClass> = []
        private let highlighter = SyntaxHighlighter()
        private static var requestedLanguages: Set<NLLanguage> = []

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            lastEditedRange = NSRange(location: range.location, length: (replacementString as NSString?)?.length ?? 0)
            shiftCodeBlocks(replacing: range, with: lastEditedRange!.length)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            guard !textView.hasMarkedText() else { return }   // never restyle mid-composition
            if let edited = lastEditedRange { restyleParagraphs(around: edited) }
            scheduleFullRestyle()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let range = textView.selectedRange()
            if parent.selection != range { parent.selection = range }
            applyFocus()
            textView.centerCaret()
            // Composition just ended: catch up on styling skipped while text was marked.
            if !textView.hasMarkedText(), pendingRestyle == nil, lastEditedRange != nil { scheduleFullRestyle() }
        }

        func restyleAll() {
            guard let textView, let storage = textView.textStorage else { return }
            let styles = MarkdownStyler.styles(for: textView.string)
            codeBlocks = styles.filter { $0.style == .codeBlock }.map(\.range)
            codeRanges = styles.filter { $0.style == .codeBlock || $0.style == .inlineCode }.map(\.range)
            AttributeApplier.applyStyles(styles, to: storage, in: NSRange(location: 0, length: storage.length),
                                         baseFont: textView.baseFont)
        }

        func observeScrolling(of scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(clipViewDidScroll),
                                                   name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            // A new window starts small and then takes its size; colour the text that resizing reveals.
            scrollView.contentView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(clipViewDidResize),
                                                   name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        }

        @objc private func clipViewDidResize(_ notification: Notification) {
            if !parent.highlightClasses.isEmpty { applyRenderingColors() }
        }

        @objc private func clipViewDidScroll(_ notification: Notification) {
            reportTopLine()
            if !parent.highlightClasses.isEmpty { applyRenderingColors() }
        }

        func reportTopLine() {
            guard let report = parent.onTopLineChange, let textView else { return }
            let visible = textView.visibleRect
            let point = NSPoint(x: textView.textContainerInset.width + 1, y: visible.minY + textView.textContainerInset.height)
            let index = textView.characterIndexForInsertion(at: point)
            report(PreviewRenderer.line(atUTF16Offset: index, in: textView.string))
        }

        /// Kept for callers that only think about focus; colours are applied together.
        func applyFocus() { applyRenderingColors() }

        /// Applies every colour that is display-only, as TextKit 2 rendering attributes (which override the
        /// stored colour without touching the text storage): focus dimming, then part-of-speech highlights.
        /// Highlighted words outside the focused range keep their hue at reduced opacity.
        func applyRenderingColors() {
            guard let textView, let tlm = textView.textLayoutManager else { return }
            appliedFocusMode = parent.focusMode
            appliedHighlightClasses = parent.highlightClasses
            let text = textView.string
            let length = (text as NSString).length
            tlm.removeRenderingAttribute(.foregroundColor, for: tlm.documentRange)

            let bright = FocusController.brightRange(in: text, selection: textView.selectedRange(), mode: parent.focusMode)
            if let bright {
                let dimmed = [NSRange(location: 0, length: bright.location),
                              NSRange(location: NSMaxRange(bright), length: length - NSMaxRange(bright))]
                for range in dimmed where range.length > 0 { setColor(Theme.dimmed, range, tlm) }
            }

            guard !parent.highlightClasses.isEmpty else { return }
            let visible = visibleRangeWithMargin()
            requestLanguageModelIfNeeded(for: (text as NSString).substring(with: visible))
            for highlight in highlighter.highlights(in: text, range: visible, excluding: codeRanges)
            where parent.highlightClasses.contains(highlight.lexicalClass) {
                let isDimmed = bright.map { NSIntersectionRange($0, highlight.range).length == 0 } ?? false
                setColor(Theme.highlight(highlight.lexicalClass, dimmed: isDimmed), highlight.range, tlm)
            }
        }

        private func setColor(_ color: NSColor, _ range: NSRange, _ tlm: NSTextLayoutManager) {
            if let textRange = Self.textRange(range, in: tlm) {
                tlm.addRenderingAttribute(.foregroundColor, value: color, for: textRange)
            }
        }

        /// The visible text plus one screen above and below, from TextKit 2's layout fragments.
        /// (Hit-testing points with `characterIndexForInsertion` fails in the text insets, where it returns the end.)
        private func visibleRangeWithMargin() -> NSRange {
            guard let textView, let tlm = textView.textLayoutManager else { return NSRange() }
            let visible = textView.visibleRect
            let origin = textView.textContainerOrigin
            let area = visible.insetBy(dx: 0, dy: -visible.height).offsetBy(dx: -origin.x, dy: -origin.y)
            tlm.ensureLayout(for: area)   // TextKit 2 lays out lazily
            let document = tlm.documentRange
            let lower = tlm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, area.minY)))?.rangeInElement.location
                ?? document.location
            let upper = tlm.textLayoutFragment(for: CGPoint(x: 0, y: area.maxY))?.rangeInElement.endLocation
                ?? document.endLocation
            let start = tlm.offset(from: document.location, to: lower)
            let end = tlm.offset(from: document.location, to: upper)
            return NSRange(location: start, length: max(0, end - start))
        }

        /// Asks NaturalLanguage once per language per launch to download a missing tagging model,
        /// then re-colours. Languages Apple has no model for (e.g. Swedish) simply stay uncoloured.
        private func requestLanguageModelIfNeeded(for text: String) {
            guard let language = SyntaxHighlighter.needsAssets(text),
                  !Self.requestedLanguages.contains(language) else { return }
            Self.requestedLanguages.insert(language)
            NLTagger.requestAssets(for: language, tagScheme: .lexicalClass) { [weak self] result, _ in
                guard result == .available else { return }
                Task { @MainActor in self?.applyRenderingColors() }
            }
        }

        private static func textRange(_ range: NSRange, in tlm: NSTextLayoutManager) -> NSTextRange? {
            guard let start = tlm.location(tlm.documentRange.location, offsetBy: range.location),
                  let end = tlm.location(start, offsetBy: range.length) else { return nil }
            return NSTextRange(location: start, end: end)
        }

        /// Fast path while typing: re-style the edited paragraph and one paragraph on each side.
        private func restyleParagraphs(around edited: NSRange) {
            guard let textView, let storage = textView.textStorage else { return }
            let ns = textView.string as NSString
            var range = ns.paragraphRange(for: NSIntersectionRange(edited, NSRange(location: 0, length: ns.length)))
            if range.location > 0 { range = NSUnionRange(range, ns.paragraphRange(for: NSRange(location: range.location - 1, length: 0))) }
            if NSMaxRange(range) < ns.length { range = NSUnionRange(range, ns.paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))) }
            for block in codeBlocks where block.location <= NSMaxRange(range) && range.location <= NSMaxRange(block) {
                range = NSUnionRange(range, ns.paragraphRange(for: NSIntersectionRange(block, NSRange(location: 0, length: ns.length))))
            }
            let styles = MarkdownStyler.styles(for: ns.substring(with: range)).map {
                StyledRange(range: NSRange(location: $0.range.location + range.location, length: $0.range.length), style: $0.style)
            }
            AttributeApplier.applyStyles(styles, to: storage, in: range, baseFont: textView.baseFont)
        }

        private func shiftCodeBlocks(replacing edited: NSRange, with newLength: Int) {
            codeBlocks = Self.shift(codeBlocks, replacing: edited, with: newLength)
            codeRanges = Self.shift(codeRanges, replacing: edited, with: newLength)
        }

        private static func shift(_ ranges: [NSRange], replacing edited: NSRange, with newLength: Int) -> [NSRange] {
            let delta = newLength - edited.length
            return ranges.map { block in
                if block.location >= NSMaxRange(edited) {
                    NSRange(location: block.location + delta, length: block.length)
                } else if NSMaxRange(block) >= edited.location {
                    NSRange(location: block.location, length: max(0, block.length + delta))
                } else {
                    block
                }
            }
        }

        private func scheduleFullRestyle() {
            pendingRestyle?.cancel()
            pendingRestyle = Task { [weak self] in
                try? await Task.sleep(for: Self.restyleDelay)
                guard !Task.isCancelled, let self else { return }
                self.pendingRestyle = nil
                if self.textView?.hasMarkedText() == true { return }
                self.lastEditedRange = nil
                self.restyleAll()
                self.applyRenderingColors()   // code ranges are fresh now
            }
        }
    }
}
