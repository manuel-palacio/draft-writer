import DraftKit
import SwiftUI

struct StatsFooter: View {
    let stats: TextStats

    var body: some View {
        Text(Self.label(for: stats))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    static func label(for stats: TextStats, locale: Locale = .current) -> String {
        func count(_ n: Int, _ singular: String, _ plural: String) -> String {
            "\(n.formatted(.number.locale(locale))) \(n == 1 ? singular : plural)"
        }
        return [count(stats.words, "word", "words"),
                count(stats.characters, "character", "characters"),
                "\(stats.readingMinutes) min"].joined(separator: " · ")
    }
}
