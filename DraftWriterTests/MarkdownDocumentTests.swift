import Foundation
import Testing
@testable import Draft_Writer

@Suite struct MarkdownDocumentTests {
    @Test func keepsCRLFWhenSaving() {
        var document = MarkdownDocument(data: Data("One\r\nTwo".utf8))
        document.text += "\nThree"   // the editor types bare LF
        #expect(String(decoding: document.data(), as: UTF8.self) == "One\r\nTwo\r\nThree")
    }

    @Test func lfFilesStayLF() {
        var document = MarkdownDocument(data: Data("One\nTwo".utf8))
        document.text += "\nThree"
        #expect(String(decoding: document.data(), as: UTF8.self) == "One\nTwo\nThree")
    }

    @Test func newDocumentsUseLF() {
        #expect(String(decoding: MarkdownDocument(text: "a\nb").data(), as: UTF8.self) == "a\nb")
    }
}
