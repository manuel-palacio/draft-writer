import SwiftUI

@main
struct DraftWriterApp: App {
    @State private var settings = EditorSettings.shared
    @State private var library = LibraryStore.shared

    init() {
        #if DEBUG
        for font in EditorFont.allCases {
            assert(Theme.font(font, size: 17).fontName.hasPrefix("iAWriter"), "Bundled iA font \(font) did not load")
        }
        #endif
        LibraryStore.shared.restore()
        TemplateFolder.shared.restore()
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentWindow(document: file.$document, fileURL: file.fileURL, settings: settings)
        }
        .commands {
            EditorCommands(settings: settings)
            ExportCommands(settings: settings)
            LibraryCommands(settings: settings, store: library)
        }
        Settings {
            SettingsView(settings: settings)
                .onAppear { NSApp.appearance = settings.appearance.nsAppearance }
        }
    }
}
