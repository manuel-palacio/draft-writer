import AppKit
import DraftKit
import SwiftUI

/// The palettes a document window can show: Quick Open over the library, or Jump to Heading in this document.
enum NavigationPalette: Identifiable {
    case quickOpen, headings
    var id: Self { self }
}

extension View {
    /// Lets Go > Quick Open and Go > Jump to Heading show their palette over this window.
    func navigationPalettes(text: String, library: LibraryStore, jump: Binding<EditorJump?>) -> some View {
        modifier(NavigationPalettes(text: text, library: library, jump: jump))
    }
}

private struct NavigationPalettes: ViewModifier {
    let text: String
    let library: LibraryStore
    @Binding var jump: EditorJump?
    @Environment(\.openDocument) private var openDocument
    @State private var palette: NavigationPalette?

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.navigationPalette, $palette)
            .sheet(item: $palette) { palette in
                switch palette {
                case .quickOpen: quickOpen
                case .headings: jumpToHeading
                }
            }
    }

    private var quickOpen: some View {
        let notes = Library.notes(in: library.items)
        return PaletteView(prompt: "Open note", entries: notes.enumerated().map { index, note in
            PaletteEntry(id: index, title: (note.name as NSString).deletingPathExtension, detail: folder(of: note.url))
        }) { entry in
            open(notes[entry.id].url)
        }
    }

    private var jumpToHeading: some View {
        let headings = HeadingOutline.headings(in: text)
        return PaletteView(prompt: "Jump to heading", entries: headings.enumerated().map { index, heading in
            PaletteEntry(id: index, title: heading.title, indent: heading.level - 1)
        }) { entry in
            jump = EditorJump(location: headings[entry.id].location)
        }
    }

    /// The note's folder relative to the library root, to tell apart notes with the same name.
    private func folder(of url: URL) -> String {
        guard let root = library.root?.standardizedFileURL.path else { return "" }
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        return parent.hasPrefix(root) ? String(parent.dropFirst(root.count)).trimmingCharacters(in: ["/"]) : ""
    }

    private func open(_ url: URL) {
        Task { @MainActor in
            do { try await openDocument(at: url) } catch { NSApp.presentError(error) }
        }
    }
}
