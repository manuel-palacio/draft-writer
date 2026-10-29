import SwiftUI

extension FocusedValues {
    /// The frontmost document window's palette, shown by the Go menu.
    @Entry var navigationPalette: Binding<NavigationPalette?>?
}

/// Go menu: Quick Open (⇧⌘O) over the library's notes, and Jump to Heading (⇧⌘J) in the current document.
struct NavigationCommands: Commands {
    @FocusedValue(\.navigationPalette) private var palette
    let store: LibraryStore

    var body: some Commands {
        CommandMenu("Go") {
            Button("Quick Open…") { palette?.wrappedValue = .quickOpen }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(palette == nil || store.root == nil)
            Button("Jump to Heading…") { palette?.wrappedValue = .headings }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(palette == nil)
        }
    }
}
