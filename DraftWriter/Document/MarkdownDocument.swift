import DraftKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown, .plainText]
    static let writableContentTypes: [UTType] = [.markdown, .plainText]

    var text: String
    /// True when the file was not valid UTF-8 and was read as Latin-1; it is saved back as UTF-8.
    var openedWithFallbackEncoding = false
    /// The file's line-break style, re-applied on save (newlines typed in the editor are LF).
    private(set) var lineEnding = LineEnding.lf

    init(text: String = "") {
        self.text = text
    }

    init(data: Data) {
        (text, openedWithFallbackEncoding) = TextDecoding.decode(data)
        lineEnding = LineEnding.detect(in: text)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.init(data: data)
    }

    /// The file contents: UTF-8, every line break in the file's original style.
    func data() -> Data {
        Data(lineEnding.apply(to: text).utf8)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data())
    }
}
