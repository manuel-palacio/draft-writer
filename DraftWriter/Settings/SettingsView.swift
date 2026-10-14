import SwiftUI

struct SettingsView: View {
    @Bindable var settings: EditorSettings

    var body: some View {
        Form {
            Picker("Font", selection: $settings.font) {
                ForEach(EditorFont.allCases) { Text($0.displayName).tag($0) }
            }
            Stepper(value: $settings.fontSize, in: EditorSettings.fontSizeRange, step: 1) {
                Text("Size: \(Int(settings.fontSize)) pt")
            }
            Slider(value: Binding(get: { Double(settings.columnWidth) },
                                  set: { settings.columnWidth = Int($0) }),
                   in: Double(EditorSettings.columnWidthRange.lowerBound)...Double(EditorSettings.columnWidthRange.upperBound),
                   step: 5) {
                Text("Line width: \(settings.columnWidth) characters")
            }
            Picker("Appearance", selection: $settings.appearance) {
                Text("Automatic").tag(Appearance.auto)
                Text("Light").tag(Appearance.light)
                Text("Dark").tag(Appearance.dark)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
