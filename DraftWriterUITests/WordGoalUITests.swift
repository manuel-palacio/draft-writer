import XCTest

/// Set a word goal from the footer, see the progress, and find the goal again after reopening the document.
/// (The document already has words: the footer hides while typing, and synthesized pointer moves don't bring
/// it back reliably.)
@MainActor
final class WordGoalUITests: XCTestCase {
    func testWordGoalProgressAndPersistence() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "goal-\(UUID().uuidString).md")
        try "One two three".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.open(url)
        app.activate()
        addTeardownBlock { app.terminate() }
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15))

        setGoal("5", in: app)
        expectProgress("3 / 5 words", in: app)

        app.typeKey("w", modifierFlags: .command)
        app.open(url)
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15))
        expectProgress("3 / 5 words", in: app)

        app.buttons["statsFooter"].click()
        app.buttons["wordGoalClear"].click()
        XCTAssertTrue(app.staticTexts["wordGoalProgress"].waitForNonExistence(timeout: 5))
    }

    private func setGoal(_ target: String, in app: XCUIApplication) {
        let footer = app.buttons["statsFooter"]
        XCTAssertTrue(footer.waitForExistence(timeout: 10))
        footer.click()
        let field = app.textFields["wordGoalField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(target + "\r")
    }

    private func expectProgress(_ text: String, in app: XCUIApplication) {
        let progress = app.staticTexts["wordGoalProgress"]
        let shown = expectation(for: NSPredicate(format: "value == %@", text), evaluatedWith: progress)
        wait(for: [shown], timeout: 10)
    }
}
