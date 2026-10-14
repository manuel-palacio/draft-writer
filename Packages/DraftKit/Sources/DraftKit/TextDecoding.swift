import Foundation

/// Turns a file's bytes into editable text: UTF-8 first, ISO Latin-1 as the fallback
/// (Latin-1 maps every byte, so decoding never fails).
public enum TextDecoding {
    public static func decode(_ data: Data) -> (text: String, usedFallback: Bool) {
        let bom = Data([0xEF, 0xBB, 0xBF])
        let body = data.starts(with: bom) ? data.dropFirst(bom.count) : data
        if let text = String(data: body, encoding: .utf8) {
            return (text, false)
        }
        return (String(data: data, encoding: .isoLatin1) ?? "", true)
    }
}
