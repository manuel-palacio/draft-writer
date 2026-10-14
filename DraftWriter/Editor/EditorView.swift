import AppKit
import DraftKit
import SwiftUI

/// Hosts `DraftTextView` in SwiftUI and keeps it in sync with the document text.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var font: NSFont
    var columnWidth: Int
    var focusMode: FocusMode = .off
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
        let focusChanged = coordinator.appliedFocusMode != focusMode
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
            AttributeApplier.applyStyles(styles, to: storage, in: NSRange(location: 0, length: storage.length),
                                         baseFont: textView.baseFont)
        }

        func observeScrolling(of scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(clipViewDidScroll),
                                                   name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        }

        @objc private func clipViewDidScroll(_ notification: Notification) {
            reportTopLine()
        }

        func reportTopLine() {
            guard let report = parent.onTopLineChange, let textView else { return }
            let visible = textView.visibleRect
            let point = NSPoint(x: textView.textContainerInset.width + 1, y: visible.minY + textView.textContainerInset.height)
            let index = textView.characterIndexForInsertion(at: point)
            report(PreviewRenderer.line(atUTF16Offset: index, in: textView.string))
        }

        /// Dims everything outside the current sentence or paragraph with a rendering attribute,
        /// which overrides the stored colour without touching the text storage.
        func applyFocus() {
            guard let textView, let tlm = textView.textLayoutManager else { return }
            appliedFocusMode = parent.focusMode
            tlm.removeRenderingAttribute(.foregroundColor, for: tlm.documentRange)
            guard let bright = FocusController.brightRange(in: textView.string, selection: textView.selectedRange(),
                                                           mode: parent.focusMode) else { return }
            let length = (textView.string as NSString).length
            let dimmed = [NSRange(location: 0, length: bright.location),
                          NSRange(location: NSMaxRange(bright), length: length - NSMaxRange(bright))]
            for range in dimmed where range.length > 0 {
                if let textRange = Self.textRange(range, in: tlm) {
                    tlm.addRenderingAttribute(.foregroundColor, value: Theme.dimmed, for: textRange)
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
            let delta = newLength - edited.length
            codeBlocks = codeBlocks.map { block in
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
            }
        }
    }
}
