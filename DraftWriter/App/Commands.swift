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
            Toggle("Syntax Highlight", isOn: $settings.syntaxHighlight)
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Menu("Highlight") {
                ForEach(LexicalClass.allCases, id: \.self) { lexicalClass in
                    Toggle(lexicalClass.title, isOn: Binding(
                        get: { settings.highlightClasses.contains(lexicalClass) },
                        set: { on in
                            if on { settings.highlightClasses.insert(lexicalClass) } else { settings.highlightClasses.remove(lexicalClass) }
                        }))
                }
                Divider()
                ForEach(StyleCheck.allCases, id: \.self) { check in
                    Toggle(check.title, isOn: Binding(
                        get: { settings.styleChecks.contains(check) },
                        set: { on in
                            if on { settings.styleChecks.insert(check) } else { settings.styleChecks.remove(check) }
                        }))
                }
            }
            .disabled(!settings.syntaxHighlight)
            Divider()
        }
    }
}

extension LexicalClass {
    var title: String {
        switch self {
        case .noun: "Nouns"
        case .verb: "Verbs"
        case .adjective: "Adjectives"
        case .adverb: "Adverbs"
        case .conjunction: "Conjunctions"
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

extension StyleCheck {
    var title: String {
        switch self {
        case .filler: "Fillers"
        case .cliche: "Clichés"
        case .redundancy: "Redundancies"
        }
    }
}
