import AppKit
import DraftKit
import Observation

enum Appearance: String, CaseIterable, Identifiable {
    case auto, light, dark

    var id: Self { self }

    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// App-wide editor settings, persisted in UserDefaults.
@MainActor @Observable
final class EditorSettings {
    static let shared = EditorSettings()

    static let fontSizeRange: ClosedRange<Double> = 12...28
    static let columnWidthRange: ClosedRange<Int> = 40...120

    var font: EditorFont { didSet { store(font.rawValue, "font") } }
    var fontSize: Double {
        didSet {
            let clamped = fontSize.clamped(to: Self.fontSizeRange)
            if clamped != fontSize { fontSize = clamped } else { store(fontSize, "fontSize") }
        }
    }
    var columnWidth: Int {
        didSet {
            let clamped = columnWidth.clamped(to: Self.columnWidthRange)
            if clamped != columnWidth { columnWidth = clamped } else { store(columnWidth, "columnWidth") }
        }
    }
    var appearance: Appearance {
        didSet {
            store(appearance.rawValue, "appearance")
            NSApp?.appearance = appearance.nsAppearance
        }
    }
    var focusMode: FocusMode { didSet { store(focusMode.rawValue, "focusMode") } }
    var typewriter: Bool { didSet { store(typewriter, "typewriter") } }
    var showPreview: Bool { didSet { store(showPreview, "showPreview") } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        font = defaults.string(forKey: "font").flatMap(EditorFont.init) ?? .duo
        fontSize = (defaults.object(forKey: "fontSize") as? Double ?? 17).clamped(to: Self.fontSizeRange)
        columnWidth = (defaults.object(forKey: "columnWidth") as? Int ?? 70).clamped(to: Self.columnWidthRange)
        appearance = defaults.string(forKey: "appearance").flatMap(Appearance.init) ?? .auto
        focusMode = defaults.string(forKey: "focusMode").flatMap(FocusMode.init) ?? .off
        typewriter = defaults.bool(forKey: "typewriter")
        showPreview = defaults.bool(forKey: "showPreview")
    }

    var editorFont: NSFont { Theme.font(font, size: fontSize) }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
