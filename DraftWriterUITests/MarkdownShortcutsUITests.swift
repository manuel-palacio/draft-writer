import XCTest

/// The Format menu shortcuts and list keys, typed into the real app.
final class MarkdownShortcutsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var editor: XCUIElement!
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "shortcuts-\(UUID().uuidString).md")
        try "".write(to: url, atomically: true, encoding: .utf8)
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.open(url)
        app.activate()
        editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.click()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: url)
    }

    private var text: String { editor.value as? String ?? "" }

    func testBoldItalicAndLinkShortcuts() {
        app.typeKey("b", modifierFlags: .command)
        editor.typeText("bold")
        app.typeKey(.rightArrow, modifierFlags: .command)
        editor.typeText(" ")
        app.typeKey("i", modifierFlags: .command)
        editor.typeText("it")
        app.typeKey(.rightArrow, modifierFlags: .command)
        editor.typeText(" site")
        app.typeKey(.leftArrow, modifierFlags: [.shift, .option])   // select "site"
        app.typeKey("k", modifierFlags: .command)
        editor.typeText("https://x.io")
        XCTAssertEqual(text, "**bold** *it* [site](https://x.io)")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(text, "**bold** *it* [site]()")
    }

    func testListKeysAndTaskToggle() {
        editor.typeText("1. one\ntwo\n")
        XCTAssertEqual(text, "1. one\n2. two\n3. ")
        editor.typeText("\n- [ ] task\n")   // Return on the empty "3. " ends the list on that line
        XCTAssertEqual(text, "1. one\n2. two\n- [ ] task\n- [ ] ")
        editor.typeText("sub")
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertEqual(text, "1. one\n2. two\n- [ ] task\n    - [ ] sub")
        app.typeKey(.tab, modifierFlags: .shift)
        XCTAssertEqual(text, "1. one\n2. two\n- [ ] task\n- [ ] sub")
        app.typeKey("l", modifierFlags: [.command, .shift])
        XCTAssertEqual(text, "1. one\n2. two\n- [ ] task\n- [x] sub")
        editor.typeText("\n\n")
        XCTAssertEqual(text, "1. one\n2. two\n- [ ] task\n- [x] sub\n")
    }
}
