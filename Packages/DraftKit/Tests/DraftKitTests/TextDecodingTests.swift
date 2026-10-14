import Foundation
import Testing
@testable import DraftKit

@Suite struct TextDecodingTests {
    @Test func decodesUTF8() {
        let result = TextDecoding.decode(Data("Hej på dig 👋".utf8))
        #expect(result.text == "Hej på dig 👋")
        #expect(result.usedFallback == false)
    }

    @Test func decodesLatin1Fallback() {
        let result = TextDecoding.decode(Data([0x48, 0xE5, 0x6C]))
        #expect(result.text == "Hål")
        #expect(result.usedFallback == true)
    }

    @Test func decodesWindows1252() {
        let result = TextDecoding.decode(Data([0x93, 0x68, 0x94, 0x20, 0x80]))
        #expect(result.text == "\u{201C}h\u{201D} €")
        #expect(result.usedFallback == true)
    }

    @Test func decodesUTF16WithBOM() {
        let result = TextDecoding.decode(Data([0xFF, 0xFE]) + "Hej å".data(using: .utf16LittleEndian)!)
        #expect(result.text == "Hej å")
        #expect(result.usedFallback == true)   // saved back as UTF-8
    }

    @Test func preservesCRLF() {
        #expect(TextDecoding.decode(Data("a\r\nb".utf8)).text == "a\r\nb")
    }

    @Test func stripsNothingButBOM() {
        let result = TextDecoding.decode(Data([0xEF, 0xBB, 0xBF]) + Data("x".utf8))
        #expect(result.text == "x")
        #expect(result.usedFallback == false)
    }
}
