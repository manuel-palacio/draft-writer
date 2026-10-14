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

    @Test func preservesCRLF() {
        #expect(TextDecoding.decode(Data("a\r\nb".utf8)).text == "a\r\nb")
    }

    @Test func stripsNothingButBOM() {
        let result = TextDecoding.decode(Data([0xEF, 0xBB, 0xBF]) + Data("x".utf8))
        #expect(result.text == "x")
        #expect(result.usedFallback == false)
    }
}
