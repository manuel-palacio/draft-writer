import Foundation

/// Writes a ZIP archive of stored (uncompressed) entries: all an OOXML package needs, with no dependencies.
enum ZipArchive {
    /// Entry names must be ASCII. Timestamps are fixed (1980-01-01), so the same input gives the same bytes.
    static func stored(_ entries: [(name: String, data: Data)]) -> Data {
        var archive = Data()
        var directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let fields = EntryFields(crc: crc32(entry.data), size: UInt32(entry.data.count), nameLength: UInt16(name.count))
            let offset = UInt32(archive.count)
            archive.append(le32: 0x0403_4B50)
            archive.append(fields.localHeader)
            archive.append(name)
            archive.append(entry.data)
            directory.append(le32: 0x0201_4B50)
            directory.append(le16: 20)   // version made by
            directory.append(fields.localHeader)
            directory.append(Data(count: 10))   // comment length, disk, internal and external attributes
            directory.append(le32: offset)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(le32: 0x0605_4B50)
        archive.append(Data(count: 4))   // disk numbers
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: UInt32(directory.count))
        archive.append(le32: directoryOffset)
        archive.append(le16: 0)   // comment length
        return archive
    }

    /// The header fields shared by the local header and the central directory record.
    private struct EntryFields {
        let crc: UInt32
        let size: UInt32
        let nameLength: UInt16

        var localHeader: Data {
            var data = Data()
            data.append(le16: 20)   // version needed
            data.append(le16: 0)    // flags
            data.append(le16: 0)    // method: stored
            data.append(le16: 0)    // time 00:00
            data.append(le16: 0x21) // date 1980-01-01
            data.append(le32: crc)
            data.append(le32: size)  // compressed
            data.append(le32: size)  // uncompressed
            data.append(le16: nameLength)
            data.append(le16: 0)    // extra field length
            return data
        }
    }

    private static let crcTable: [UInt32] = (0..<256).map { byte in
        (0..<8).reduce(UInt32(byte)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(le32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
