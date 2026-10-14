import SwiftUI

@main
struct DraftWriterApp: App {
    @State private var settings = EditorSettings.shared

    init() {
        #if DEBUG
        for font in EditorFont.allCases {
            assert(Theme.font(font, size: 17).fontName.hasPrefix("iAWriter"), "Bundled iA font \(font) did not load")
        }
        #endif
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            TextEditor(text: file.$document.text)
        }
        Settings {
            SettingsView(settings: settings)
                .onAppear { NSApp.appearance = settings.appearance.nsAppearance }
        }
    }
}
