import Foundation
import Testing
@testable import DraftKit

@Suite struct HeadingOutlineTests {
    @Test func listsAtxHeadingsWithLevelsAndTitles() {
        let text = "# One\n\ntext\n\n## Two ##\n\n###### Six *deep*\n"
        let headings = HeadingOutline.headings(in: text)
        #expect(headings.map(\.level) == [1, 2, 6])
        #expect(headings.map(\.title) == ["One", "Two", "Six deep"])
    }

    @Test func reportsUTF16LocationOfEachHeading() {
        let text = "Café ☕️\n\n## Après\n"
        let headings = HeadingOutline.headings(in: text)
        let expected = (text as NSString).range(of: "## Après").location
        #expect(headings.map(\.location) == [expected])
    }

    @Test func listsSetextHeadings() {
        let text = "Title\n=====\n\nSection\n-------\n\nbody\n"
        let headings = HeadingOutline.headings(in: text)
        #expect(headings.map(\.level) == [1, 2])
        #expect(headings.map(\.title) == ["Title", "Section"])
        #expect(headings.map(\.location) == [0, (text as NSString).range(of: "Section").location])
    }

    @Test func ignoresHashesInsideCodeBlocks() {
        let text = "# Real\n\n```sh\n# a shell comment\n```\n\n    # indented code\n\n## Also real\n"
        #expect(HeadingOutline.headings(in: text).map(\.title) == ["Real", "Also real"])
    }

    @Test func emptyDocumentHasNoHeadings() {
        #expect(HeadingOutline.headings(in: "").isEmpty)
        #expect(HeadingOutline.headings(in: "just text\n#not a heading").isEmpty)
    }
}
