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
    /// Where Jump to Heading last asked the caret to go.
    var jump: EditorJump? = nil

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
            coordinator.replaceText(with: text)
            needsRestyle = true
        }
        if needsRestyle { coordinator.restyleAll() }
        if focusChanged || needsRestyle { coordinator.applyFocus() }
        if let jump, jump != coordinator.lastJump { coordinator.reveal(jump) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        static let restyleDelay: Duration = .milliseconds(150)

        var parent: EditorView
        weak var textView: DraftTextView?
        private var pendingRestyle: Task<Void, Never>?
        private var lastEditedRange: NSRange?
        private(set) var appliedFocusMode: FocusMode = .off
        /// The last jump carried out, so a view update doesn't repeat it.
        var lastJump: EditorJump?
        /// Fenced code blocks from the last full pass, shifted as text is edited, so the fast path
        /// can re-parse a whole block instead of a fragment that loses its fences.
        private var codeBlocks: [NSRange] = []
        private var lineIndex: LineIndex?
        private var lastReportedLine = 0
        /// Inline code and code blocks from the last full pass; never highlighted.
        private var inlineCode: [NSRange] = []
        /// Code that part-of-speech highlighting leaves alone.
        private var codeRanges: [NSRange] { codeBlocks + inlineCode }
        private(set) var appliedHighlightClasses: Set<LexicalClass> = []
        /// Ranges the last colour pass set, so a caret move clears only those instead of the whole document.
        /// After an edit the next pass clears everything once: TextKit 2 doesn't move rendering attributes
        /// predictably with edited text.
        private var colouredRanges: [NSRange] = []
        private var clearsWholeDocument = true
        private let highlighter = SyntaxHighlighter()
        private static var requestedLanguages: Set<NLLanguage> = []
        static let modelRetryDelay: Duration = .seconds(60)

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            lastEditedRange = NSRange(location: range.location, length: (replacementString as NSString?)?.length ?? 0)
            shiftCodeBlocks(replacing: range, with: lastEditedRange!.length)
            clearsWholeDocument = true
            return true
        }

        /// External change (revert, undo through the document): replaces the text, keeps the caret in range,
        /// and clears the undo stack, whose steps refer to ranges of the old text. (NSTextView registers its
        /// steps with a private target, so they can't be removed selectively.)
        func replaceText(with text: String) {
            guard let textView else { return }
            let caret = min(textView.selectedRange().location, (text as NSString).length)
            textView.string = text
            textView.undoManager?.removeAllActions()
            lineIndex = nil
            clearsWholeDocument = true
            textView.setSelectedRange(NSRange(location: caret, length: 0))
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            lineIndex = nil
            clearsWholeDocument = true   // a colour pass during the edit may have used locations from before it
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
            inlineCode = styles.filter { $0.style == .inlineCode }.map(\.range)
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

        /// Tells the preview which source line is at the top. The line index is rebuilt only after edits,
        /// and the report is sent only when the line changes, outside the current view update.
        func reportTopLine() {
            guard let report = parent.onTopLineChange, let textView, let tlm = textView.textLayoutManager else { return }
            let origin = textView.textContainerOrigin
            let top = max(0, textView.visibleRect.minY - origin.y)
            let document = tlm.documentRange
            let location = tlm.textLayoutFragment(for: CGPoint(x: 0, y: top))?.rangeInElement.location ?? document.location
            if lineIndex == nil { lineIndex = LineIndex(textView.string) }
            let line = lineIndex!.line(atUTF16Offset: tlm.offset(from: document.location, to: location))
            guard line != lastReportedLine else { return }
            lastReportedLine = line
            Task { @MainActor in report(line) }
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
            clearRenderingColors(tlm)

            let bright = FocusController.brightRange(in: text, selection: textView.selectedRange(), mode: parent.focusMode)
            if let bright {
                let dimmed = [NSRange(location: 0, length: bright.location),
                              NSRange(location: NSMaxRange(bright), length: length - NSMaxRange(bright))]
                for range in dimmed where range.length > 0 { setColor(Theme.dimmed, range, tlm) }
            }

            guard !parent.highlightClasses.isEmpty else { return }
            let visible = visibleRangeWithMargin()
            for highlight in highlighter.highlights(in: text, range: visible, excluding: codeRanges)
            where parent.highlightClasses.contains(highlight.lexicalClass) {
                let isDimmed = bright.map { NSIntersectionRange($0, highlight.range).length == 0 } ?? false
                setColor(Theme.highlight(highlight.lexicalClass, dimmed: isDimmed), highlight.range, tlm)
            }
            requestMissingLanguageModels()
        }

        private func setColor(_ color: NSColor, _ range: NSRange, _ tlm: NSTextLayoutManager) {
            if let textRange = Self.textRange(range, in: tlm) {
                tlm.addRenderingAttribute(.foregroundColor, value: color, for: textRange)
                colouredRanges.append(range)
            }
        }

        private func clearRenderingColors(_ tlm: NSTextLayoutManager) {
            if clearsWholeDocument {
                tlm.removeRenderingAttribute(.foregroundColor, for: tlm.documentRange)
                clearsWholeDocument = false
            } else {
                for range in colouredRanges where range.length > 0 {
                    if let textRange = Self.textRange(range, in: tlm) { tlm.removeRenderingAttribute(.foregroundColor, for: textRange) }
                }
            }
            colouredRanges.removeAll(keepingCapacity: true)
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

        /// Asks NaturalLanguage to download the tagging model for each language the highlighter met without one,
        /// then re-colours. Each language is asked once per launch, unless the request failed (e.g. offline),
        /// which is retried a minute later. Languages Apple has no model for (e.g. Swedish) stay uncoloured.
        private func requestMissingLanguageModels() {
            for language in highlighter.missingLanguages where !Self.requestedLanguages.contains(language) {
                Self.requestedLanguages.insert(language)
                NLTagger.requestAssets(for: language, tagScheme: .lexicalClass) { [weak self] result, _ in
                    Task { @MainActor in
                        switch result {
                        case .available: self?.applyRenderingColors()
                        case .error:
                            // Allow another try later (e.g. back online), not on every keystroke.
                            try? await Task.sleep(for: Self.modelRetryDelay)
                            Self.requestedLanguages.remove(language)
                        default: break
                        }
                    }
                }
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
            // Called before the edit, so the text view still has the old length. An unclosed fence runs to the
            // end of the document and keeps growing as you type there; inline code never does.
            let length = (textView?.string as NSString?)?.length ?? 0
            codeBlocks = Self.shift(codeBlocks, replacing: edited, with: newLength, documentLength: length)
            inlineCode = Self.shift(inlineCode, replacing: edited, with: newLength)
        }

        /// Moves `ranges` through an edit that replaced `edited` with `newLength` characters. An end point
        /// inside the replaced text lands at the end of the new text, so the part of a range that survives a
        /// deletion stays covered. Text inserted right after a range isn't part of it, unless the range runs
        /// to the end of the document (`documentLength`, before the edit) and so does the insertion.
        static func shift(_ ranges: [NSRange], replacing edited: NSRange, with newLength: Int,
                          documentLength: Int? = nil) -> [NSRange] {
            let delta = newLength - edited.length
            func start(_ p: Int) -> Int {
                p < edited.location ? p : p >= NSMaxRange(edited) ? p + delta : edited.location + newLength
            }
            func end(_ p: Int) -> Int {
                p <= edited.location ? p : p >= NSMaxRange(edited) ? p + delta : edited.location + newLength
            }
            return ranges.map { range in
                let lower = start(range.location)
                let atDocumentEnd = NSMaxRange(range) == documentLength && edited.location == documentLength
                let upper = atDocumentEnd ? NSMaxRange(range) + delta : end(NSMaxRange(range))
                return NSRange(location: lower, length: max(0, upper - lower))
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
