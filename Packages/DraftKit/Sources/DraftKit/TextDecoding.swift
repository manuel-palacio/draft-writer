import Foundation

/// Turns a file's bytes into editable text. Tries, in order: UTF-16 (only with a byte-order mark),
/// UTF-8, Windows-1252 (what most "Latin-1" files from Windows really are), then ISO Latin-1,
/// which maps every byte, so decoding never fails. Anything but UTF-8 is reported as a fallback,
/// because the document is saved back as UTF-8.
public enum TextDecoding {
    public static func decode(_ data: Data) -> (text: String, usedFallback: Bool) {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return (text, true)
        }
        let bom = Data([0xEF, 0xBB, 0xBF])
        let body = data.starts(with: bom) ? data.dropFirst(bom.count) : data
        if let text = String(data: body, encoding: .utf8) {
            return (text, false)
        }
        let text = String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return (text, true)
    }
}
