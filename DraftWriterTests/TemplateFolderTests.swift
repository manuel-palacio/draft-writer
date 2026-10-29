import Foundation
import Testing
@testable import Draft_Writer

@MainActor
@Suite struct TemplateFolderTests {
    let defaults: UserDefaults
    let folder: URL

    init() throws {
        defaults = UserDefaults(suiteName: "TemplateFolderTests-\(UUID().uuidString)")!
        folder = FileManager.default.temporaryDirectory.appending(path: "template-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "b {}".write(to: folder.appending(path: "b.css"), atomically: true, encoding: .utf8)
        try "a {}".write(to: folder.appending(path: "a.css"), atomically: true, encoding: .utf8)
        try "not css".write(to: folder.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
    }

    @Test func startsBuiltIn() {
        let templates = TemplateFolder(defaults: defaults)
        templates.restore()
        #expect(templates.url == nil)
        #expect(templates.css == nil)
    }

    @Test func joinsTheFolderCSSFilesInNameOrder() throws {
        let templates = TemplateFolder(defaults: defaults)
        try templates.choose(folder)
        #expect(templates.css == "a {}\nb {}")
    }

    @Test func folderWithoutCSSIsRejected() throws {
        let empty = folder.appending(path: "empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let templates = TemplateFolder(defaults: defaults)
        #expect(throws: TemplateFolderError.self) { try templates.choose(empty) }
        #expect(templates.css == nil)
        #expect(defaults.data(forKey: TemplateFolder.bookmarkKey) == nil)
    }

    @Test func restoresAfterRelaunch() throws {
        try TemplateFolder(defaults: defaults).choose(folder)
        let relaunched = TemplateFolder(defaults: defaults)
        relaunched.restore()
        #expect(relaunched.url?.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path)
        #expect(relaunched.css == "a {}\nb {}")
    }

    @Test func unreadableFolderFallsBackToBuiltIn() throws {
        try TemplateFolder(defaults: defaults).choose(folder)
        try FileManager.default.removeItem(at: folder)
        let relaunched = TemplateFolder(defaults: defaults)
        relaunched.restore()
        #expect(relaunched.url == nil)
        #expect(relaunched.css == nil)
        #expect(defaults.data(forKey: TemplateFolder.bookmarkKey) == nil)
    }

    @Test func useBuiltInForgetsTheFolder() throws {
        let templates = TemplateFolder(defaults: defaults)
        try templates.choose(folder)
        templates.useBuiltIn()
        #expect(templates.url == nil && templates.css == nil)
        let relaunched = TemplateFolder(defaults: defaults)
        relaunched.restore()
        #expect(relaunched.css == nil)
    }
}
