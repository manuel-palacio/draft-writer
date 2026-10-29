import XCTest

/// File > Revert To replaces the text from outside the editor; undoing afterwards must not touch stale ranges.
final class RevertUndoUITests: XCTestCase {
    func testUndoAfterRevertDoesNotCrash() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "revert-\(UUID().uuidString).md")
        try "Saved text".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.open(url)
        app.activate()
        addTeardownBlock { app.terminate() }
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText(" and a long unsaved tail that undo would refer to")

        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Revert To"].hover()
        // Titled "Last Opened — <time>" or "Last Saved Version", depending on the document's history.
        let lastSaved = app.menuItems["revertDocumentToSaved:"]
        XCTAssertTrue(lastSaved.waitForExistence(timeout: 5))
        lastSaved.click()
        let confirm = app.sheets.buttons["Revert"]
        if confirm.waitForExistence(timeout: 2) { confirm.click() }
        let reverted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Saved text"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [reverted], timeout: 5), .completed)

        app.typeKey("z", modifierFlags: .command)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(editor.value as? String, "Saved text")
    }
}
