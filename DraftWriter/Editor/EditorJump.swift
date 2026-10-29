import AppKit
import Foundation

/// A request to move the editor's caret, e.g. to a heading. Each request is distinct, so choosing
/// the same heading twice jumps twice.
struct EditorJump: Equatable {
    let id = UUID()
    /// UTF-16 offset in the document.
    let location: Int
}

extension EditorView.Coordinator {
    /// Puts the caret at the jump's location, scrolls it into view and gives the editor keyboard focus.
    func reveal(_ jump: EditorJump) {
        lastJump = jump
        guard let textView else { return }
        let caret = NSRange(location: min(jump.location, (textView.string as NSString).length), length: 0)
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(caret)
        textView.scrollRangeToVisible(caret)
    }
}
