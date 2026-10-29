import XCTest

/// Set a word goal from the footer, watch the progress follow the typing, and find the goal again after reopening.
@MainActor
final class WordGoalUITests: XCTestCase {
    func testWordGoalProgressAndPersistence() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "goal-\(UUID().uuidString).md")
        try "".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let app = XCUIApplication()
        app.open(url)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))

        setGoal("5", in: app)
        expectProgress("0 / 5 words", in: app)

        editor.click()
        editor.typeText("one two three")
        app.windows.firstMatch.hover()   // the footer fades out while typing
        expectProgress("3 / 5 words", in: app)

        app.typeKey("s", modifierFlags: .command)
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
