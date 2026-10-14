import AppKit
import DraftKit
import SwiftUI

/// Hosts `DraftTextView` in SwiftUI and keeps it in sync with the document text.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var font: NSFont
    var columnWidth: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = DraftTextView.make()
        textView.delegate = context.coordinator
        textView.baseFont = font
        textView.columnWidth = columnWidth
        textView.string = text
        context.coordinator.textView = textView
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
        if textView.string != text {
            // External change (revert, undo through the document): replace and keep the caret in range.
            let caret = min(textView.selectedRange().location, (text as NSString).length)
            textView.string = text
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            needsRestyle = true
        }
        if needsRestyle { coordinator.restyleAll() }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        static let restyleDelay: Duration = .milliseconds(150)

        var parent: EditorView
        weak var textView: DraftTextView?
        private var pendingRestyle: Task<Void, Never>?
        private var lastEditedRange: NSRange?

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            lastEditedRange = NSRange(location: range.location, length: (replacementString as NSString?)?.length ?? 0)
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
            // Composition just ended: catch up on styling skipped while text was marked.
            if !textView.hasMarkedText(), pendingRestyle == nil, lastEditedRange != nil { scheduleFullRestyle() }
        }

        func restyleAll() {
            guard let textView, let storage = textView.textStorage else { return }
            let styles = MarkdownStyler.styles(for: textView.string)
            AttributeApplier.applyStyles(styles, to: storage, in: NSRange(location: 0, length: storage.length),
                                         baseFont: textView.baseFont)
        }

        /// Fast path while typing: re-style the edited paragraph and one paragraph on each side.
        private func restyleParagraphs(around edited: NSRange) {
            guard let textView, let storage = textView.textStorage else { return }
            let ns = textView.string as NSString
            var range = ns.paragraphRange(for: NSIntersectionRange(edited, NSRange(location: 0, length: ns.length)))
            if range.location > 0 { range = NSUnionRange(range, ns.paragraphRange(for: NSRange(location: range.location - 1, length: 0))) }
            if NSMaxRange(range) < ns.length { range = NSUnionRange(range, ns.paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))) }
            let styles = MarkdownStyler.styles(for: ns.substring(with: range)).map {
                StyledRange(range: NSRange(location: $0.range.location + range.location, length: $0.range.length), style: $0.style)
            }
            AttributeApplier.applyStyles(styles, to: storage, in: range, baseFont: textView.baseFont)
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
