import Foundation
import Testing
@testable import Draft_Writer

@Suite struct WordGoalTests {
    let enUS = Locale(identifier: "en_US")

    @Test func rejectsNonPositiveTargets() {
        #expect(WordGoal(target: 0) == nil)
        #expect(WordGoal(target: -5) == nil)
        #expect(WordGoal(target: 1)?.target == 1)
    }

    @Test func parsesTypedTargets() {
        #expect(WordGoal(parsing: "1,000")?.target == 1000)
        #expect(WordGoal(parsing: " 750 ")?.target == 750)
        #expect(WordGoal(parsing: "1.000")?.target == 1000)
        #expect(WordGoal(parsing: "1\u{00A0}000")?.target == 1000)
        #expect(WordGoal(parsing: "") == nil)
        #expect(WordGoal(parsing: "lots") == nil)
        #expect(WordGoal(parsing: "0") == nil)
    }

    @Test func progressLabel() throws {
        let goal = try #require(WordGoal(target: 1000))
        #expect(goal.label(words: 820, locale: enUS) == "820 / 1,000 words")
        #expect(try #require(WordGoal(target: 1)).label(words: 0, locale: enUS) == "0 / 1 word")
    }

    @Test func fractionIsCappedAtOne() throws {
        let goal = try #require(WordGoal(target: 200))
        #expect(goal.fraction(words: 0) == 0)
        #expect(goal.fraction(words: 50) == 0.25)
        #expect(goal.fraction(words: 500) == 1)
    }

    @Test func reachedAtTarget() throws {
        let goal = try #require(WordGoal(target: 200))
        #expect(!goal.isReached(words: 199))
        #expect(goal.isReached(words: 200))
        #expect(goal.isReached(words: 201))
    }
}

@Suite struct WordGoalStoreTests {
    let store = WordGoalStore(defaults: UserDefaults(suiteName: "WordGoalStoreTests-\(UUID().uuidString)")!)
    let essay = URL(filePath: "/tmp/Essay.md")
    let notes = URL(filePath: "/tmp/Notes.md")

    @Test func remembersGoalsPerFile() {
        store.setGoal(WordGoal(target: 500), for: essay)
        store.setGoal(WordGoal(target: 80), for: notes)
        #expect(store.goal(for: essay)?.target == 500)
        #expect(store.goal(for: notes)?.target == 80)
    }

    @Test func survivesANewStoreOnTheSameDefaults() {
        store.setGoal(WordGoal(target: 500), for: essay)
        #expect(WordGoalStore(defaults: store.defaults).goal(for: essay)?.target == 500)
    }

    @Test func clearingForgetsTheGoal() {
        store.setGoal(WordGoal(target: 500), for: essay)
        store.setGoal(nil, for: essay)
        #expect(store.goal(for: essay) == nil)
    }

    @Test func untitledDocumentKeepsItsGoalInMemory() {
        #expect(store.carryOver(WordGoal(target: 300), to: nil)?.target == 300)
    }

    @Test func savingAnUntitledDocumentStoresItsGoal() {
        #expect(store.carryOver(WordGoal(target: 300), to: essay)?.target == 300)
        #expect(store.goal(for: essay)?.target == 300)
    }

    @Test func openingAFileLoadsItsStoredGoal() {
        store.setGoal(WordGoal(target: 500), for: essay)
        #expect(store.carryOver(nil, to: essay)?.target == 500)
        #expect(store.carryOver(WordGoal(target: 300), to: essay)?.target == 500)
    }

    @Test func fileWithoutGoalHasNone() {
        #expect(store.carryOver(nil, to: notes) == nil)
    }
}
