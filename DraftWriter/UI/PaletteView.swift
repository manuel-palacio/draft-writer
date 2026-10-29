import DraftKit
import SwiftUI

/// One row of a palette: a note or a heading.
struct PaletteEntry: Identifiable {
    let id: Int
    let title: String
    /// Secondary text after the title, e.g. a note's folder.
    var detail = ""
    /// Indentation steps, e.g. a heading's level minus one.
    var indent = 0
}

/// A search field over a list, filtered by fuzzy match, for keyboard-only navigation:
/// ↑/↓ move the selection, Return chooses it, Escape closes.
struct PaletteView: View {
    let prompt: String
    let entries: [PaletteEntry]
    let choose: (PaletteEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            results
        }
        .frame(width: 480, height: 340)
        .onAppear { searchFocused = true }
    }

    private var matches: [PaletteEntry] {
        FuzzyMatch.rank(entries, by: query, key: \.title)
    }

    private var searchField: some View {
        TextField(prompt, text: $query)
            .textFieldStyle(.plain)
            .font(.title3)
            .padding(12)
            .focused($searchFocused)
            .accessibilityIdentifier("paletteSearch")
            .onSubmit(chooseSelected)
            .onKeyPress(.downArrow) { moveSelection(by: 1) }
            .onKeyPress(.upArrow) { moveSelection(by: -1) }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
            .onChange(of: query) { selectedIndex = 0 }
    }

    private var results: some View {
        ScrollViewReader { proxy in
            List(Array(matches.enumerated()), id: \.element.id) { index, entry in
                row(entry)
                    .listRowBackground(index == selectedIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                    .onTapGesture { chooseEntry(entry) }
            }
            .listStyle(.plain)
            .onChange(of: selectedIndex) {
                if matches.indices.contains(selectedIndex) { proxy.scrollTo(matches[selectedIndex].id) }
            }
        }
    }

    private func row(_ entry: PaletteEntry) -> some View {
        HStack {
            Text(entry.title)
            Spacer()
            Text(entry.detail).foregroundStyle(.secondary)
        }
        .padding(.leading, CGFloat(entry.indent) * 14)
        .contentShape(Rectangle())
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let count = matches.count
        if count > 0 { selectedIndex = min(max(selectedIndex + offset, 0), count - 1) }
        return .handled
    }

    private func chooseSelected() {
        let current = matches
        guard current.indices.contains(selectedIndex) else { return }
        chooseEntry(current[selectedIndex])
    }

    private func chooseEntry(_ entry: PaletteEntry) {
        dismiss()
        choose(entry)
    }
}
