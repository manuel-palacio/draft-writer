import SwiftUI

@main
struct DraftWriterApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            TextEditor(text: file.$document.text)
        }
    }
}
