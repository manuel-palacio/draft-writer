import DraftKit
import SwiftUI

/// View-menu commands for the writing modes. Modes are app-wide in M1.
struct EditorCommands: Commands {
    @Bindable var settings: EditorSettings

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Focus Mode: \(settings.focusMode.title)") { settings.focusMode = settings.focusMode.next }
                .keyboardShortcut("d")
            Toggle("Typewriter Scrolling", isOn: $settings.typewriter)
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Toggle("Show Preview", isOn: $settings.showPreview)
                .keyboardShortcut("r")
            Divider()
        }
    }
}

extension FocusMode {
    var title: String {
        switch self {
        case .off: "Off"
        case .sentence: "Sentence"
        case .paragraph: "Paragraph"
        }
    }
}
