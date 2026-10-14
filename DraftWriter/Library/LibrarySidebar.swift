import AppKit
import DraftKit
import SwiftUI

/// The library: one folder of notes as a tree, with search, sorting, rename and move-to-Trash.
/// Clicking a note opens it as a normal document window (or brings its window forward).
struct LibrarySidebar: View {
    @Bindable var store: LibraryStore
    @Environment(\.openDocument) private var openDocument
    @State private var renaming: URL?
    @State private var newName = ""
    @State private var trashing: URL?
    @State private var errorMessage: String?

    var body: some View {
        content
            .searchable(text: $store.query, placement: .sidebar, prompt: "Search notes")
            .toolbar {
                ToolbarItemGroup {
                    if store.root != nil {
                        Picker("Sort", selection: $store.sort) {
                            Text("Date Modified").tag(LibrarySort.modified)
                            Text("Name").tag(LibrarySort.name)
                        }
                        .pickerStyle(.menu)
                        Button("New Note", systemImage: "square.and.pencil") { newNote() }
                    }
                }
            }
            .onChange(of: store.selection) { _, url in open(url) }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") { commitRename() }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("Move “\(trashing?.lastPathComponent ?? "")” to the Trash?",
                                isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } })) {
                Button("Move to Trash", role: .destructive) { commitTrash() }
            }
            .alert("Library", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.root == nil {
            ContentUnavailableView {
                Label("No Library", systemImage: "books.vertical")
            } description: {
                Text("Choose a folder of notes to browse and search it here.")
            } actions: {
                Button("Choose Folder…") { chooseFolder() }
            }
        } else if !store.query.isEmpty {
            List(store.searchResults, id: \.self, selection: $store.selection) { url in
                row(name: url.deletingPathExtension().lastPathComponent, url: url, isFolder: false)
            }
        } else {
            List(selection: $store.selection) {
                OutlineGroup(store.items, children: \.children) { item in
                    row(name: item.isFolder ? item.name : (item.name as NSString).deletingPathExtension,
                        url: item.url, isFolder: item.isFolder)
                }
            }
            .contextMenu {
                Button("Choose Another Folder…") { chooseFolder() }
            }
        }
    }

    private func row(name: String, url: URL, isFolder: Bool) -> some View {
        Label(name, systemImage: isFolder ? "folder" : "doc.text")
            .tag(url)
            .contextMenu {
                if !isFolder {
                    Button("Rename…") {
                        newName = url.deletingPathExtension().lastPathComponent
                        renaming = url
                    }
                    Button("Move to Trash…", role: .destructive) { trashing = url }
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
    }

    private func open(_ url: URL?) {
        guard let url, Library.fileExtensions.contains(url.pathExtension.lowercased()) else { return }
        Task { @MainActor in
            do { try await openDocument(at: url) } catch { errorMessage = error.localizedDescription }
        }
    }

    private func newNote() {
        do {
            let url = try store.newNote(in: store.targetFolder)
            open(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitRename() {
        guard let url = renaming else { return }
        renaming = nil
        do { try store.rename(url, to: newName) } catch { errorMessage = error.localizedDescription }
    }

    private func commitTrash() {
        guard let url = trashing else { return }
        trashing = nil
        do { try store.trash(url) } catch { errorMessage = error.localizedDescription }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder that holds your notes."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.choose(url) } catch { errorMessage = error.localizedDescription }
    }
}
