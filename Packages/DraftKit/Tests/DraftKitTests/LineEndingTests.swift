import Testing
@testable import DraftKit

@Suite struct LineEndingTests {
    @Test func detectsFromFirstBreak() {
        #expect(LineEnding.detect(in: "a\r\nb\nc") == .crlf)
        #expect(LineEnding.detect(in: "a\nb\r\nc") == .lf)
        #expect(LineEnding.detect(in: "a\rb") == .cr)
        #expect(LineEnding.detect(in: "no breaks") == .lf)
    }

    @Test func normalizesMixedEndings() {
        // A CRLF file after typing: the typed newline is a bare LF.
        #expect(LineEnding.crlf.apply(to: "a\r\nb\nc\rd") == "a\r\nb\r\nc\r\nd")
        #expect(LineEnding.lf.apply(to: "a\r\nb\rc") == "a\nb\nc")
        #expect(LineEnding.cr.apply(to: "a\r\nb\nc") == "a\rb\rc")
    }

    @Test func emojiAndCombiningMarksSurvive() {
        #expect(LineEnding.crlf.apply(to: "é👋🏽\nx") == "é👋🏽\r\nx")
    }
}
