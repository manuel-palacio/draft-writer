import AppKit
import SwiftUI

struct LibraryCommands: Commands {
    @Bindable var settings: EditorSettings
    let store: LibraryStore
    @Environment(\.openDocument) private var openDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Note in Library") {
                Task { @MainActor in
                    await Self.newNote(store: store, open: { try await openDocument(at: $0) },
                                       report: { NSApp.presentError($0) })
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(store.root == nil)
        }
        CommandGroup(before: .sidebar) {
            Toggle("Show Library", isOn: $settings.showLibrary)
                .keyboardShortcut("1")
        }
    }

    /// Creates a note in the library's target folder and opens it; any failure goes to `report`.
    @MainActor
    static func newNote(store: LibraryStore, open: (URL) async throws -> Void, report: (any Error) -> Void) async {
        do {
            try await open(store.newNote(in: store.targetFolder))
        } catch {
            report(error)
        }
    }
}
