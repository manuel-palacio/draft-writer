import XCTest

/// File > Revert To replaces the text from outside the editor; undoing afterwards must not touch stale ranges.
final class RevertUndoUITests: XCTestCase {
    func testUndoAfterRevertDoesNotCrash() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "revert-\(UUID().uuidString).md")
        try "Saved text".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let app = XCUIApplication()
        app.open(url)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText(" and a long unsaved tail that undo would refer to")

        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        fileMenu.menuItems["Revert To"].hover()
        fileMenu.menuItems["Last Saved Version"].click()
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
