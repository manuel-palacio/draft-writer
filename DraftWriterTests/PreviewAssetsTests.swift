import Foundation
import Testing
@testable import Draft_Writer

@Suite struct PreviewAssetsTests {
    let folder = URL(fileURLWithPath: "/tmp/d", isDirectory: true)

    func resolve(_ string: String, folder: URL?) -> URL? {
        PreviewAssets.fileURL(for: URL(string: string)!, documentFolder: folder, bundle: .main)
    }

    @Test func resolvesDocumentRelative() {
        #expect(resolve("draft-asset://doc/img/a.png", folder: folder)?.path == "/tmp/d/img/a.png")
    }

    @Test func decodesPercentEscapes() {
        #expect(resolve("draft-asset://doc/my%20pic.png", folder: folder)?.path == "/tmp/d/my pic.png")
    }

    @Test func rejectsTraversal() {
        #expect(resolve("draft-asset://doc/../../etc/passwd", folder: folder) == nil)
        #expect(resolve("draft-asset://doc/img/%2E%2E/%2E%2E/etc/passwd", folder: folder) == nil)
    }

    @Test func rejectsAbsolute() {
        #expect(resolve("draft-asset://doc//etc/passwd", folder: folder) == nil)
    }

    @Test func rejectsSymlinkOutOfFolder() throws {
        let fm = FileManager.default
        let doc = fm.temporaryDirectory.appending(path: "assets-\(UUID().uuidString)/doc")
        let outside = doc.deletingLastPathComponent().appending(path: "outside")
        try fm.createDirectory(at: doc.appending(path: "img"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try "secret".write(to: outside.appending(path: "secret.txt"), atomically: true, encoding: .utf8)
        try "png".write(to: doc.appending(path: "img/a.png"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: doc.appending(path: "link"), withDestinationURL: outside)
        #expect(resolve("draft-asset://doc/link/secret.txt", folder: doc) == nil)
        #expect(resolve("draft-asset://doc/img/a.png", folder: doc) != nil)
    }

    @Test func noFolderResolvesNothing() {
        #expect(resolve("draft-asset://doc/img/a.png", folder: nil) == nil)
    }

    @Test func resolvesBundledFont() throws {
        let url = try #require(resolve("draft-asset://app/fonts/iAWriterDuoS-Regular.ttf", folder: nil))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(resolve("draft-asset://app/fonts/../Info.plist", folder: nil) == nil)
    }

    @Test func previewCSSUsesScheme() {
        let css = PreviewAssets.previewCSS()
        #expect(css.contains("draft-asset://app/fonts/iAWriterDuoS-Regular.ttf"))
        #expect(css.contains("prefers-color-scheme: dark"))
    }

    @Test func exportCSSIsSelfContained() {
        let css = PreviewAssets.exportCSS()
        #expect(css.contains("data:font/ttf;base64,"))
        #expect(!css.contains("draft-asset:"))
        #expect(!css.contains("prefers-color-scheme"))
    }

    @Test func previewCSSUsesChosenFont() {
        let css = PreviewAssets.previewCSS(font: .quattro)
        #expect(css.contains("--body-font: \"iA Writer Quattro\""))
        #expect(css.contains("draft-asset://app/fonts/iAWriterQuattroS-BoldItalic.ttf"))
        #expect(css.contains("draft-asset://app/fonts/iAWriterMonoS-Bold.ttf"))   // code gets real bold, not synthesized
    }

    @Test func exportCSSInlinesOnlyNeededFonts() {
        let css = PreviewAssets.exportCSS(font: .quattro)
        #expect(css.contains("--body-font: \"iA Writer Quattro\""))
        #expect(css.contains("font-family: \"iA Writer Quattro\""))
        #expect(css.contains("font-family: \"iA Writer Mono\""))
        #expect(!css.contains("font-family: \"iA Writer Duo\""))
    }
}
