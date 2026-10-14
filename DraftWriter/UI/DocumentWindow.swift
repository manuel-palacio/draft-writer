import DraftKit
import SwiftUI

/// One document window: the editor, the stats footer and the encoding banner.
/// The footer and toolbar fade out while typing and come back when the mouse moves.
struct DocumentWindow: View {
    static let statsDelay: Duration = .milliseconds(300)

    @Binding var document: MarkdownDocument
    @Bindable var settings: EditorSettings
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var stats = TextStats(words: 0, characters: 0, readingMinutes: 0)
    @State private var isTyping = false
    @State private var bannerDismissed = false

    var body: some View {
        VStack(spacing: 0) {
            if document.openedWithFallbackEncoding && !bannerDismissed {
                encodingBanner
            }
            EditorView(text: $document.text, selection: $selection,
                       font: settings.editorFont, columnWidth: settings.columnWidth,
                       focusMode: settings.focusMode, typewriter: settings.typewriter)
            StatsFooter(stats: stats)
                .padding(.vertical, 6)
                .opacity(isTyping ? 0 : 1)
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(Color(nsColor: Theme.background))
        .animation(.easeInOut(duration: 0.3), value: isTyping)
        .toolbarVisibility(isTyping ? .hidden : .automatic, for: .windowToolbar)
        .onContinuousHover { _ in if isTyping { isTyping = false } }
        .onChange(of: document.text) { isTyping = true }
        .task(id: StatsInput(text: document.text, selection: selection)) { await updateStats() }
    }

    private var encodingBanner: some View {
        HStack {
            Text("Opened as Latin-1. Draft Writer will save this file as UTF-8.")
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
