import Foundation
import Testing
@testable import DraftKit

@Suite struct NoteLinksTests {
    func substrings(_ text: String, _ style: MarkdownStyle) -> [String] {
        MarkdownStyler.styles(for: text).filter { $0.style == style }.map { (text as NSString).substring(with: $0.range) }
    }

    @Test func wikilinksAreStyledWithGreyedBrackets() {
        let text = "See [[Other Note]] and [[ Spaced ]]."
        #expect(substrings(text, .wikilink) == ["[[Other Note]]", "[[ Spaced ]]"])
        #expect(substrings(text, .syntaxMarker) == ["[[", "]]", "[[", "]]"])
    }

    @Test func wikilinkNameAtLocation() {
        let text = "a [[Other Note]] b [[]] c"
        let ns = text as NSString
        #expect(NoteLinks.wikilink(in: text, at: ns.range(of: "Other").location) == "Other Note")
        #expect(NoteLinks.wikilink(in: text, at: ns.range(of: "[[O").location) == "Other Note")
        #expect(NoteLinks.wikilink(in: text, at: ns.range(of: " b").location) == nil)
        #expect(NoteLinks.wikilink(in: text, at: ns.range(of: "[[]]").location) == nil)
    }

    @Test func tagsAreStyled() {
        let text = "Ideas #draft, #work-in-progress and #växt.\n\n# Heading #inline"
        #expect(substrings(text, .tag) == ["#draft", "#work-in-progress", "#växt", "#inline"])
    }

    @Test func notTags() {
        let text = "# Heading\n\nIssue #42, x.io/#frag, C#, &#38; [a](#anchor) ##double"
        #expect(substrings(text, .tag).isEmpty)
    }

    @Test func codeIsNeitherLinkNorTag() {
        let text = "`[[Name]] #tag`\n\n```\n[[Name]] #tag\n```"
        #expect(substrings(text, .tag).isEmpty)
        #expect(substrings(text, .wikilink).isEmpty)
    }

    @Test func tagNamesAreCollectedLowercased() {
        #expect(NoteLinks.tags(in: "#Draft #draft #Work `#code`") == ["draft", "work"])
    }

    @Test func findsNoteByNameWithAnyExtension() {
        let notes = ["a/Other Note.md", "b/plan.txt", "c/Other.markdown"].map { URL(filePath: "/lib/\($0)") }
        #expect(Library.note(named: "other note", in: notes)?.lastPathComponent == "Other Note.md")
        #expect(Library.note(named: "Plan", in: notes)?.lastPathComponent == "plan.txt")
        #expect(Library.note(named: "Other.markdown", in: notes)?.lastPathComponent == "Other.markdown")
        #expect(Library.note(named: "Missing", in: notes) == nil)
    }

    @Test func createsANamedNote() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try Library.createNote(named: "New Idea", in: folder)
        #expect(url.lastPathComponent == "New Idea.md")
        #expect(throws: (any Error).self) { try Library.createNote(named: "New Idea", in: folder) }
        #expect(throws: (any Error).self) { try Library.createNote(named: "a/b", in: folder) }
    }
}
