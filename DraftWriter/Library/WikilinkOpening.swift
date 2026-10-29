import AppKit
import SwiftUI

extension View {
    /// Opens the library note a `[[Note]]` link names when `name` is set (⌘-click in the editor).
    func wikilinkOpening(library: LibraryStore, name: Binding<String?>) -> some View {
        modifier(WikilinkOpening(library: library, name: name))
    }
}

/// Opens the library note of that name in its own window, or offers to create it in the library's target folder.
private struct WikilinkOpening: ViewModifier {
    let library: LibraryStore
    @Binding var name: String?
    @Environment(\.openDocument) private var openDocument
    @State private var missing: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: name) { _, requested in
                guard let requested else { return }
                name = nil
                if let url = library.note(named: requested) {
                    open(url)
                } else if library.root != nil {
                    missing = requested
                } else {
                    NSSound.beep()   // no library to look in or create the note in
                }
            }
            .confirmationDialog("There is no note called “\(missing ?? "")”.",
                                isPresented: Binding(get: { missing != nil }, set: { if !$0 { missing = nil } })) {
                Button("Create Note") { create() }
            } message: {
                Text("Create it in the library?")
            }
    }

    private func create() {
        guard let missing else { return }
        self.missing = nil
        do { open(try library.createNote(named: missing)) } catch { NSApp.presentError(error) }
    }

    private func open(_ url: URL) {
        Task { @MainActor in
            do { try await openDocument(at: url) } catch { NSApp.presentError(error) }
        }
    }
}
