import SwiftUI

/// One document window: the editor (and, from Task 7, the stats footer).
struct DocumentWindow: View {
    @Binding var document: MarkdownDocument
    @Bindable var settings: EditorSettings
    @State private var selection = NSRange(location: 0, length: 0)

    var body: some View {
        EditorView(text: $document.text, selection: $selection,
                   font: settings.editorFont, columnWidth: settings.columnWidth)
            .frame(minWidth: 480, minHeight: 320)
            .background(Color(nsColor: Theme.background))
    }
}
