import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension FocusedValues {
    /// The frontmost document window's content, for File > Export and Print.
    @Entry var exportSource: ExportSource?
}

struct ExportCommands: Commands {
    @FocusedValue(\.exportSource) private var source
    let settings: EditorSettings

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Export as HTML…") { if let source { exportHTML(source) } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(source == nil)
            Button("Export as PDF…") { if let source { exportPDF(source) } }
                .disabled(source == nil)
            Button("Export as Word…") { if let source { exportWord(source) } }
                .disabled(source == nil)
            Divider()
            Button("Print…") {
                guard let source else { return }
                Task { @MainActor in
                    do { try await Exporter.print(source, pageSize: settings.pageSize) } catch { show(error) }
                }
            }
            .keyboardShortcut("p")
            .disabled(source == nil)
        }
    }

    @MainActor
    private func exportHTML(_ source: ExportSource) {
        chooseDestination(for: source, type: .html) { url in
            try Exporter.html(source).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    private func exportPDF(_ source: ExportSource) {
        chooseDestination(for: source, type: .pdf) { url in
            Task { @MainActor in
                do { try await Exporter.writePDF(source, to: url, pageSize: settings.pageSize) } catch { show(error) }
            }
        }
    }

    @MainActor
    private func exportWord(_ source: ExportSource) {
        chooseDestination(for: source, type: UTType(filenameExtension: "docx") ?? .data) { url in
            try Exporter.docx(source).write(to: url, options: .atomic)
        }
    }

    @MainActor
    private func chooseDestination(for source: ExportSource, type: UTType, write: @escaping (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = source.title
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try write(url) } catch { show(error) }
        }
    }

    @MainActor
    private func show(_ error: any Error) {
        NSAlert(error: error).runModal()
    }
}
