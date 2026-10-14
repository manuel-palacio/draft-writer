import XCTest

/// End-to-end: open a file, type, save, close, reopen, and check both the window and the bytes on disk.
final class DraftWriterUITests: XCTestCase {
    func testTypeSaveReopen() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "smoke-\(UUID().uuidString).md")
        try "".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let app = XCUIApplication()
        app.open(url)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.click()
        editor.typeText("# Smoke\n\nHello")
        app.typeKey("s", modifierFlags: .command)
        app.typeKey("w", modifierFlags: .command)

        app.open(url)
        let reopened = app.textViews.firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 15))
        XCTAssertEqual(reopened.value as? String, "# Smoke\n\nHello")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# Smoke\n\nHello")
    }
}
