import AppKit
import SwiftUI

/// Settings row for the preview/export template: the built-in stylesheet or a chosen folder of CSS.
struct TemplateFolderPicker: View {
    let templates: TemplateFolder

    var body: some View {
        LabeledContent("Template folder") {
            HStack {
                Text(templates.url?.lastPathComponent ?? "Built-in")
                    .foregroundStyle(.secondary)
                    .help(templates.url?.path ?? "The app's own stylesheet")
                Button("Choose…", action: chooseFolder)
                if templates.url != nil {
                    Button("Use Built-in") { templates.useBuiltIn() }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder of CSS files. They replace the built-in stylesheet in the preview and in exports."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try templates.choose(url) } catch { NSAlert(error: error).runModal() }
        }
    }
}
