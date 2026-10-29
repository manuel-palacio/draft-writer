import XCTest

/// Quick Open and Jump to Heading, driven from the keyboard only.
@MainActor
final class NavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    func testQuickOpenOpensANoteByFuzzyName() throws {
        launchWithUntitledDocument(environment: try library(["Alpha.md": "Alpha body", "Sub/Gamma Draft.md": "Gamma body", "Beta.md": "Beta body"]))

        app.typeKey("o", modifierFlags: [.command, .shift])
        let search = app.textFields["paletteSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.typeText("gmdr")
        XCTAssertTrue(app.staticTexts["Gamma Draft"].waitForExistence(timeout: 10))
        search.typeText("\r")

        let opened = app.textViews.matching(NSPredicate(format: "value == %@", "Gamma body")).firstMatch
        XCTAssertTrue(opened.waitForExistence(timeout: 15))
    }

    func testJumpToHeadingMovesTheCaret() {
        launchWithUntitledDocument()
        let editor = app.textViews.firstMatch
        editor.typeText("# One\n\nFirst\n\n## Two\n\nSecond\n\n### Three\n\nThird")

        app.typeKey("j", modifierFlags: [.command, .shift])
        let search = app.textFields["paletteSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.typeKey(.downArrow, modifierFlags: [])
        search.typeText("\r")
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))

        // Focus is back in the editor with the caret at the start of "## Two".
        app.typeText("X")
        XCTAssertEqual(editor.value as? String, "# One\n\nFirst\n\nX## Two\n\nSecond\n\n### Three\n\nThird")
    }

    func testCommandClickOnAWikilinkOpensTheNote() throws {
        launchWithUntitledDocument(environment: try library(["Alpha.md": "Alpha body", "Beta.md": "Beta body"]))
        commandClickFirstLine(of: String(repeating: "[[Beta]]", count: 12))
        let opened = app.textViews.matching(NSPredicate(format: "value == %@", "Beta body")).firstMatch
        XCTAssertTrue(opened.waitForExistence(timeout: 15))
    }

    func testCommandClickOnAMissingWikilinkOffersToCreateTheNote() throws {
        launchWithUntitledDocument(environment: try library(["Alpha.md": "Alpha body"]))
        commandClickFirstLine(of: "[[Gamma is a note whose long name fills the whole first line of the column]]")
        let create = app.windows.buttons["Create Note"].firstMatch   // not the Touch Bar copy
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.click()
        let created = app.windows.matching(NSPredicate(format: "title BEGINSWITH %@", "Gamma")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 15))
    }

    /// Types `text`, which must fill the editor's first line with link, then ⌘-clicks the middle of that line.
    private func commandClickFirstLine(of text: String) {
        let editor = app.textViews.firstMatch
        editor.typeText(text)
        app.typeKey(.upArrow, modifierFlags: .command)   // scrolled to the top, so the first line is on screen
        let firstLine = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 52))
        XCUIElement.perform(withKeyModifiers: .command) { firstLine.click() }
    }

    private func launchWithUntitledDocument(environment: [String: String] = [:]) {
        app = XCUIApplication()
        app.launchEnvironment = environment
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        addTeardownBlock { [app] in app?.terminate() }
        let editor = app.textViews.firstMatch
        if !editor.waitForExistence(timeout: 5) { app.typeKey("n", modifierFlags: .command) }
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.click()
    }

    /// A launch environment that gives the app a library of `notes` (relative path → text) for this launch.
    private func library(_ notes: [String: String]) throws -> [String: String] {
        ["DRAFT_LIBRARY_FIXTURE": String(decoding: try JSONEncoder().encode(notes), as: UTF8.self)]
    }
}
