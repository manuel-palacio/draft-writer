import DraftKit
import SwiftUI

/// One document window: the editor, the stats footer and the encoding banner.
/// The footer and toolbar fade out while typing and come back when the mouse moves.
struct DocumentWindow: View {
    static let statsDelay: Duration = .milliseconds(300)

    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @Bindable var settings: EditorSettings
    var library: LibraryStore = .shared
    var templates: TemplateFolder = .shared
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var stats = TextStats(words: 0, characters: 0, readingMinutes: 0)
    @State private var isTyping = false
    @State private var bannerDismissed = false
    @State private var topLine = 1
    @State private var jump: EditorJump?

    var body: some View {
        NavigationSplitView(columnVisibility: libraryVisibility) {
            LibrarySidebar(store: library)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            VStack(spacing: 0) {
                if document.openedWithFallbackEncoding && !bannerDismissed {
                    encodingBanner
                }
                HSplitView {
                    EditorView(text: $document.text, selection: $selection,
                               font: settings.editorFont, columnWidth: settings.columnWidth,
                               focusMode: settings.focusMode, highlightClasses: settings.activeHighlightClasses,
                               typewriter: settings.typewriter,
                               onTopLineChange: settings.showPreview ? { topLine = $0 } : nil, jump: jump)
                        .frame(minWidth: 360)
                    if settings.showPreview {
                        PreviewView(markdown: document.text, documentFolder: fileURL?.deletingLastPathComponent(),
                                    topLine: topLine, font: settings.font, templateCSS: templates.css)
                            .frame(minWidth: 320)
                    }
                }
                StatsFooter(stats: stats)
                    .padding(.vertical, 6)
                    .opacity(isTyping ? 0 : 1)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(Color(nsColor: Theme.background))
        .animation(.easeInOut(duration: 0.3), value: isTyping)
        .toolbarVisibility(isTyping ? .hidden : .automatic, for: .windowToolbar)
        .onContinuousHover { _ in if isTyping { isTyping = false } }
        .onChange(of: document.text) { isTyping = true }
        .focusedSceneValue(\.exportSource, ExportSource(markdown: document.text, title: title,
                                                         documentFolder: fileURL?.deletingLastPathComponent(),
                                                         font: settings.font, templateCSS: templates.css))
        .task(id: StatsInput(text: document.text, selection: selection)) { await updateStats() }
        .navigationPalettes(text: document.text, library: library, jump: $jump)
    }

    /// ⌘1 / View > Show Library, kept in sync with the sidebar's own toggle button.
    private var libraryVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { settings.showLibrary ? .all : .detailOnly },
                set: { settings.showLibrary = $0 != .detailOnly })
    }

    private var title: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    private var encodingBanner: some View {
        HStack {
            Text("This file was not UTF-8. Draft Writer will save it as UTF-8.")
            Spacer()
            Button("Dismiss") { bannerDismissed = true }
        }
        .font(.callout)
        .padding(8)
        .background(.yellow.opacity(0.2))
    }

    private func updateStats() async {
        do { try await Task.sleep(for: Self.statsDelay) } catch { return }
        let text = document.text as NSString
        let selected = NSIntersectionRange(selection, NSRange(location: 0, length: text.length))
        let source = selected.length > 0 ? text.substring(with: selected) : document.text
        let result = await Task.detached { TextStats.compute(source) }.value
        if !Task.isCancelled { stats = result }
    }

    private struct StatsInput: Equatable {
        let text: String
        let selection: NSRange
    }
}
