import SwiftUI

struct LibraryCommands: Commands {
    @Bindable var settings: EditorSettings
    let store: LibraryStore
    @Environment(\.openDocument) private var openDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Note in Library") {
                guard let url = try? store.newNote(in: store.targetFolder) else { return }
                Task { @MainActor in try? await openDocument(at: url) }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(store.root == nil)
        }
        CommandGroup(before: .sidebar) {
            Toggle("Show Library", isOn: $settings.showLibrary)
                .keyboardShortcut("1")
        }
    }
}
