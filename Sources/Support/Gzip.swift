import Foundation
import TypeWhisperPluginSDK

/// gzip encode/decode helpers for the Seed-ASR WebSocket payloads.
///
/// Apple's `NSData.compressed(using: .zlib)` emits **raw DEFLATE** (no zlib
/// wrapper), so on encode we wrap it directly with a gzip header + trailer,
/// and on decode we skip the (variable-length) gzip header + 8-byte trailer
/// before raw-deflate decompressing. This mirrors Python's `gzip.compress`
/// and `gzip.decompress` used by ByteDance's official sample.
enum Gzip {
    static func encode(_ data: Data) throws -> Data {
        let deflate = try (data as NSData).compressed(using: .zlib) as Data
        let crc = crc32(data)
        let isize = UInt32(data.count & 0xFFFF_FFFF)

        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        out.append(deflate)
        var crcLE = crc.littleEndian
        var isizeLE = isize.littleEndian
        withUnsafeBytes(of: &crcLE) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &isizeLE) { out.append(contentsOf: $0) }
        return out
    }

    static func decode(_ data: Data) throws -> Data {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b else {
            throw PluginTranscriptionError.networkError("Not a gzip payload")
        }
        let flg = data[3]
        var offset = 10
        if flg & 0x04 != 0 {                       // FEXTRA
            guard data.count >= offset + 2 else { throw PluginTranscriptionError.networkError("Bad gzip")
            }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flg & 0x08 != 0 {                       // FNAME (null-terminated)
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flg & 0x10 != 0 {                       // FCOMMENT
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flg & 0x02 != 0 { offset += 2 }         // FHCRC
        guard offset + 8 <= data.count else {
            throw PluginTranscriptionError.networkError("Bad gzip payload")
        }
        let deflate = data.subdata(in: offset..<(data.count - 8))
        return try (deflate as NSData).decompressed(using: .zlib) as Data
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
