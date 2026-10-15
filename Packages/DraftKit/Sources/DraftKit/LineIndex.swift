import Foundation

/// Line numbers for UTF-16 offsets, as in CommonMark: lines end at `\n`, `\r\n` or `\r`. Built once per
/// text (O(n)); each lookup is a binary search, so scroll sync stays cheap on huge documents.
public struct LineIndex: Sendable {
    /// UTF-16 offset where each line after the first starts.
    private let starts: [Int]

    public init(_ text: String) {
        var starts: [Int] = []
        var previous: UInt16 = 0
        for (offset, unit) in text.utf16.enumerated() {
            if previous == 0x0D, unit != 0x0A { starts.append(offset) }
            if unit == 0x0A { starts.append(offset + 1) }
            previous = unit
        }
        if previous == 0x0D { starts.append(text.utf16.count) }
        self.starts = starts
    }

    /// The 1-based line containing `offset`.
    public func line(atUTF16Offset offset: Int) -> Int {
        // Number of line starts at or before `offset` (hand-written binary search; the standard library has none).
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return low + 1
    }
}
