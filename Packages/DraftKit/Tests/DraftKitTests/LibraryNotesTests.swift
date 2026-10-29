import Foundation
import Testing
@testable import DraftKit

@Suite struct LibraryNotesTests {
    @Test func flattensTheTreeToNotesOnly() {
        func item(_ path: String, folder: Bool = false, _ children: [LibraryItem]? = nil) -> LibraryItem {
            LibraryItem(url: URL(filePath: "/lib/\(path)"), name: (path as NSString).lastPathComponent,
                        isFolder: folder, modified: .distantPast, children: children)
        }
        let tree = [item("sub", folder: true, [item("sub/deep", folder: true, [item("sub/deep/c.md")]), item("sub/b.md")]),
                    item("a.md")]
        #expect(Library.notes(in: tree).map(\.name) == ["c.md", "b.md", "a.md"])
    }
}
