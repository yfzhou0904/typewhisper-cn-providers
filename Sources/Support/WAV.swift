import Foundation
import TypeWhisperPluginSDK

/// Minimal WAV header parser for the audio TypeWhisper hands us.
///
/// Only the fields the ASR protocols need are read (channels, bits/sample,
/// sample rate); the full file is streamed as-is (including its header),
/// matching ByteDance's official sample.
enum WAV {
    struct Info {
        let channels: Int
        let bits: Int
        let rate: Int
    }

    /// Parse the 44-byte canonical WAV header.
    static func parse(_ data: Data) throws -> Info {
        guard data.count >= 44,
              data[0...3] == Data("RIFF".utf8),
              data[8...11] == Data("WAVE".utf8) else {
            throw PluginTranscriptionError.apiError("Audio is not a WAV file")
        }
        let channels = Int(UInt16(data[22]) | (UInt16(data[23]) << 8))
        let bits = Int(UInt16(data[34]) | (UInt16(data[35]) << 8))
        let rate = Int(UInt32(data[24]) | (UInt32(data[25]) << 8)
                            | (UInt32(data[26]) << 16) | (UInt32(data[27]) << 24))
        return Info(channels: channels, bits: bits, rate: rate)
    }

    /// Split the full WAV (including header, matching the official sample) into
    /// ~`segmentDurationMs` chunks for streaming.
    static func segments(wavData: Data, segmentDurationMs: Int) throws -> ([Data], Info) {
        let info = try parse(wavData)
        let bytesPerSecond = info.rate * info.channels * (info.bits / 8)
        let segmentSize = max(1, bytesPerSecond * segmentDurationMs / 1000)

        var segments: [Data] = []
        var offset = 0
        while offset < wavData.count {
            let end = min(wavData.count, offset + segmentSize)
            segments.append(wavData.subdata(in: offset..<end))
            offset = end
        }
        return (segments, info)
    }
}
