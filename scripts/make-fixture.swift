// Generates Packages/DraftKit/Tests/DraftKitTests/Fixtures/long.md: a deterministic
// ~50,000-word Markdown document with headings, emphasis, links, lists, quotes and code.
// Usage: swift scripts/make-fixture.swift
import Foundation

let words = ["the", "writer", "draft", "quiet", "morning", "sentence", "paragraph", "focus", "light",
             "river", "window", "simple", "clear", "garden", "letter", "story", "careful", "small", "word", "time"]
var seed: UInt64 = 42
func next() -> Int {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Int(seed >> 33)
}
func word() -> String { words[next() % words.count] }
func sentence() -> String {
    var parts = (0..<(8 + next() % 10)).map { _ in word() }
    switch next() % 6 {
    case 0: parts[2] = "*\(parts[2])*"
    case 1: parts[3] = "**\(parts[3])**"
    case 2: parts[1] = "`\(parts[1])`"
    case 3: parts[4] = "[\(parts[4])](https://example.com/\(parts[4]))"
    default: break
    }
    return parts.joined(separator: " ").prefix(1).uppercased() + parts.joined(separator: " ").dropFirst() + "."
}

var out = ""
var count = 0
var section = 1
while count < 56_000 {
    out += "\(section % 3 == 0 ? "###" : "##") Section \(section)\n\n"
    for _ in 0..<4 {
        let paragraph = (0..<(3 + next() % 4)).map { _ in sentence() }.joined(separator: " ")
        count += paragraph.split(separator: " ").count
        out += paragraph + "\n\n"
    }
    switch section % 4 {
    case 0: out += "- \(sentence())\n- \(sentence())\n- \(sentence())\n\n"
    case 1: out += "> \(sentence())\n\n"
    case 2: out += "```swift\nlet value = \(section)\nprint(value)\n```\n\n"
    default: break
    }
    count += 30
    section += 1
}
let url = URL(fileURLWithPath: "Packages/DraftKit/Tests/DraftKitTests/Fixtures/long.md")
try out.write(to: url, atomically: true, encoding: .utf8)
print("wrote \(url.path): \(out.utf8.count) bytes, \(section - 1) sections")
