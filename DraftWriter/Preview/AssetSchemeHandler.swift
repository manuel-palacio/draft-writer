import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves `draft-asset://` requests from the app process, which owns the sandbox access.
@MainActor
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    var documentFolder: URL?

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        guard let file = PreviewAssets.fileURL(for: url, documentFolder: documentFolder, bundle: .main),
              let data = try? Data(contentsOf: file) else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            task.didReceive(response)
            task.didFinish()
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
