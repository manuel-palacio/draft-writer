import XCTest

/// Quick Open and Jump to Heading, driven from the keyboard only.
@MainActor
final class NavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    func testQuickOpenOpensANoteByFuzzyName() throws {
        let library = try makeLibrary(["Alpha.md": "Alpha body", "Sub/Gamma Draft.md": "Gamma body", "Beta.md": "Beta body"])
        launchWithUntitledDocument(arguments: ["-DraftLibraryPath", library.path])

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
        launchWithUntitledDocument(arguments: [])
        let editor = app.textViews.firstMatch
        editor.typeText("# One\n\nfirst\n\n## Two\n\nsecond\n\n### Three\n\nthird")

        app.typeKey("j", modifierFlags: [.command, .shift])
        let search = app.textFields["paletteSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.typeKey(.downArrow, modifierFlags: [])
        search.typeText("\r")
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))

        // Focus is back in the editor with the caret at the start of "## Two".
        app.typeText("X")
        XCTAssertEqual(editor.value as? String, "# One\n\nfirst\n\nX## Two\n\nsecond\n\n### Three\n\nthird")
    }

    private func launchWithUntitledDocument(arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = arguments + ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        let editor = app.textViews.firstMatch
        if !editor.waitForExistence(timeout: 5) { app.typeKey("n", modifierFlags: .command) }
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.click()
    }

    /// A library folder inside the sandboxed app's container, which the app can read without a bookmark.
    private func makeLibrary(_ notes: [String: String]) throws -> URL {
        let home = URL(filePath: String(cString: getpwuid(getuid())!.pointee.pw_dir), directoryHint: .isDirectory)
        let root = home.appending(path: "Library/Containers/io.github.manuel-palacio.DraftWriter/Data/tmp/ui-library-\(UUID().uuidString)",
                                  directoryHint: .isDirectory)
        for (path, text) in notes {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
