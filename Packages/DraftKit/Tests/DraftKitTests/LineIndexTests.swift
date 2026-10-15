import Foundation
import Testing
@testable import DraftKit

@Suite struct LineIndexTests {
    @Test func lineAtOffset() {
        let index = LineIndex("a\nb\r\nc\rd")
        #expect(index.line(atUTF16Offset: 0) == 1)
        #expect(index.line(atUTF16Offset: 1) == 1)
        #expect(index.line(atUTF16Offset: 2) == 2)
        #expect(index.line(atUTF16Offset: 4) == 2)   // between \r and \n
        #expect(index.line(atUTF16Offset: 5) == 3)
        #expect(index.line(atUTF16Offset: 7) == 4)
        #expect(index.line(atUTF16Offset: 99) == 4)
    }

    @Test func emptyText() {
        #expect(LineIndex("").line(atUTF16Offset: 0) == 1)
    }

    @Test func lookupsAreFastOnHugeText() {
        let text = (1...200_000).map { "Line \($0)" }.joined(separator: "\n")
        let index = LineIndex(text)
        let clock = ContinuousClock()
        var sum = 0
        let elapsed = clock.measure {
            for offset in stride(from: 0, to: text.utf16.count, by: 100) { sum += index.line(atUTF16Offset: offset) }
        }
        #expect(sum > 0)
        #expect(elapsed < .milliseconds(50))
        #expect(index.line(atUTF16Offset: text.utf16.count) == 200_000)
    }
}
