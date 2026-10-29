import AppKit
import Testing
@testable import Draft_Writer

@MainActor
@Suite(.serialized) struct EditorSettingsTests {
    func defaults(appearance: Appearance) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "EditorSettingsTests-\(UUID().uuidString)")!
        defaults.set(appearance.rawValue, forKey: "appearance")
        return defaults
    }

    @Test func storedAppearanceAppliesAtLaunch() {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        NSApp.appearance = nil
        _ = EditorSettings(defaults: defaults(appearance: .dark))
        #expect(NSApp.appearance?.name == .darkAqua)
    }

    @Test func changingAppearanceAppliesImmediately() {
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        let settings = EditorSettings(defaults: defaults(appearance: .dark))
        settings.appearance = .light
        #expect(NSApp.appearance?.name == .aqua)
        settings.appearance = .auto
        #expect(NSApp.appearance == nil)
    }
}
