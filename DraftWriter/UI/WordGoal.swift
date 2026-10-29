import Foundation

/// A target word count for a whole document, and how far along it is.
struct WordGoal: Equatable {
    let target: Int

    init?(target: Int) {
        guard target > 0 else { return nil }
        self.target = target
    }

    /// Reads what was typed into the goal field; grouping separators of any locale ("1,000", "1 000", "1.000") are ignored.
    init?(parsing typed: String) {
        let digits = typed.filter(\.isASCII).filter(\.isNumber)
        guard let target = Int(digits) else { return nil }
        self.init(target: target)
    }

    func fraction(words: Int) -> Double {
        min(1, Double(words) / Double(target))
    }

    func isReached(words: Int) -> Bool {
        words >= target
    }

    /// "820 / 1,000 words".
    func label(words: Int, locale: Locale = .current) -> String {
        let format = IntegerFormatStyle<Int>.number.locale(locale)
        return "\(words.formatted(format)) / \(target.formatted(format)) \(target == 1 ? "word" : "words")"
    }
}

/// Word goals remembered per document, by file path. Renaming the file outside the app loses its goal.
struct WordGoalStore {
    static let key = "wordGoals"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func goal(for file: URL) -> WordGoal? {
        storedTargets()[file.path].flatMap(WordGoal.init(target:))
    }

    func setGoal(_ goal: WordGoal?, for file: URL) {
        var targets = storedTargets()
        targets[file.path] = goal?.target
        defaults.set(targets, forKey: Self.key)
    }

    /// The goal for a document whose file just changed: opened, saved for the first time, or saved elsewhere.
    /// A goal already stored for that file wins; otherwise the current one moves with the document.
    /// Untitled documents (no file) keep their goal in memory only.
    func carryOver(_ current: WordGoal?, to file: URL?) -> WordGoal? {
        guard let file else { return current }
        if let stored = goal(for: file) { return stored }
        if current != nil { setGoal(current, for: file) }
        return current
    }

    private func storedTargets() -> [String: Int] {
        defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
    }
}
