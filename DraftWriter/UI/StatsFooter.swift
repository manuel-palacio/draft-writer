import DraftKit
import SwiftUI

/// Counts for the document or the selection, plus progress towards the document's word goal.
/// Clicking the counts opens a popover to set or clear the goal.
struct StatsFooter: View {
    let stats: TextStats
    /// The goal measures the whole document, even while `stats` describe a selection.
    let documentWords: Int
    let fileURL: URL?
    var goalStore = WordGoalStore()
    @State private var goal: WordGoal?
    @State private var editingGoal = false

    var body: some View {
        HStack(spacing: 8) {
            Button { editingGoal = true } label: { Text(Self.label(for: stats)) }
                .buttonStyle(.plain)
                .help("Set a word goal")
                .accessibilityIdentifier("statsFooter")
                .popover(isPresented: $editingGoal) { WordGoalEditor(goal: goalBinding) }
            if let goal {
                goalProgress(goal)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .task(id: fileURL) { goal = goalStore.carryOver(goal, to: fileURL) }
    }

    static func label(for stats: TextStats, locale: Locale = .current) -> String {
        func number(_ n: Int) -> String { n.formatted(.number.locale(locale)) }
        func count(_ n: Int, _ singular: String, _ plural: String) -> String {
            "\(number(n)) \(n == 1 ? singular : plural)"
        }
        return [count(stats.words, "word", "words"),
                count(stats.sentences, "sentence", "sentences"),
                count(stats.characters, "character", "characters") + " (\(number(stats.charactersWithoutSpaces)) without spaces)",
                "\(stats.readingMinutes) min"].joined(separator: " · ")
    }

    private var goalBinding: Binding<WordGoal?> {
        Binding(get: { goal }, set: { newGoal in
            goal = newGoal
            if let fileURL { goalStore.setGoal(newGoal, for: fileURL) }
        })
    }

    private func goalProgress(_ goal: WordGoal) -> some View {
        let reached = goal.isReached(words: documentWords)
        return HStack(spacing: 4) {
            ProgressView(value: goal.fraction(words: documentWords))
                .controlSize(.small)
                .frame(width: 60)
                .tint(reached ? .green : .accentColor)
            Text(goal.label(words: documentWords))
                .foregroundStyle(reached ? .green : .secondary)
                .accessibilityIdentifier("wordGoalProgress")
            if reached {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Goal reached")
                    .accessibilityIdentifier("wordGoalReached")
            }
        }
    }
}

/// The popover behind the footer: type a number and press Return, or clear the goal.
private struct WordGoalEditor: View {
    @Binding var goal: WordGoal?
    @State private var typed = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Word goal", text: $typed)
                .frame(width: 160)
                .accessibilityIdentifier("wordGoalField")
                .onSubmit(apply)
            HStack {
                Button("Clear") { goal = nil; dismiss() }
                    .accessibilityIdentifier("wordGoalClear")
                    .disabled(goal == nil)
                Spacer()
                Button("Set", action: apply)
                    .accessibilityIdentifier("wordGoalSet")
            }
        }
        .padding(12)
        .onAppear { typed = goal.map { String($0.target) } ?? "" }
    }

    private func apply() {
        goal = WordGoal(parsing: typed)
        dismiss()
    }
}
