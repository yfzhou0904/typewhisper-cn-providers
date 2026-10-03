import Foundation
import os
import TypeWhisperPluginSDK

/// TypeWhisper transcription engine backed by ByteDance's (Volcengine) Seed-ASR
/// 2.0 bigmodel service, modern single-key auth.
///
/// Transport: `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream`
/// (non-streaming: stream the WAV in as binary frames, get the full-sentence
/// transcript at the end). The binary protocol mirrors ByteDance's official
/// `sauc_websocket_demo.py`:
///   4-byte header + 4-byte big-endian seq + 4-byte size + gzip payload.
/// Auth: single `X-Api-Key` header (modern console method) + `X-Api-Resource-Id`.
/// (The legacy App ID + Access Token method is supported by the server but not used.)
@objc(ByteDanceSeedASREngine)
final class ByteDanceSeedASREngine: NSObject,
    DictionaryTermHintTranscriptionEnginePlugin,
    DictionaryTermsCapabilityProviding,
    DictionaryTermsBudgetProviding,
    @unchecked Sendable {

    static let providerIdValue = "bytedance-seed-asr"
    static let providerDisplayNameValue = "ByteDance Seed ASR"

    static let pluginId = TypeWhisperCNProvidersPlugin.pluginId
    static let pluginName = TypeWhisperCNProvidersPlugin.pluginName

    private static let endpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"
    private static let resourceID = "volc.seedasr.sauc.duration"
    private static let apiKeySecretKey = "bdApiKey"
    private static let modelID = "seed-asr-2.0"
    private static let segmentDurationMs = 200
    private static let resourceTimeout: TimeInterval = 90

    private let state = ByteDanceSeedASRState()
    private let logger = Logger(subsystem: "dev.yfzhou.typewhisper-cn-providers", category: "ByteDanceSeedASR")

    required override init() {
        super.init()
    }

    func activate(host: HostServices) {
        state.activate(
            host: host,
            apiKey: host.loadSecret(key: Self.apiKeySecretKey)
        )
    }

    func deactivate() {
        state.deactivate()
    }

    // MARK: - TranscriptionEnginePlugin

    var providerId: String { Self.providerIdValue }
    var providerDisplayName: String { Self.providerDisplayNameValue }

    var isConfigured: Bool {
        guard let apiKey = state.snapshot().apiKey else { return false }
        return !apiKey.isEmpty
    }

    var transcriptionModels: [PluginModelInfo] {
        [PluginModelInfo(id: Self.modelID, displayName: "Seed-ASR 2.0 (bigmodel)")]
    }

    var selectedModelId: String? { Self.modelID }
    func selectModel(_ modelId: String) {}

    var supportsTranslation: Bool { false }

    var supportedLanguages: [String] { ["auto", "zh", "en"] }

    func transcribe(
        audio: AudioData,
        language: String?,
        translate: Bool,
        prompt: String?
    ) async throws -> PluginTranscriptionResult {
        try await transcribe(
            audio: audio,
            language: language,
            translate: translate,
            prompt: prompt,
            dictionaryTermHints: []
        )
    }

    // MARK: - Dictionary terms (Seed hotwords)
    //
    // Seed-ASR 2.0's bigmodel_nostream endpoint natively supports direct
    // hotword injection (up to 5000 words) via `request.corpus.context`.
    // TypeWhisper dictionary Terms are forwarded verbatim as recognition hints
    // (NOT converted into corrections — deterministic Corrections are applied
    // host-side by TypeWhisper itself).

    var dictionaryTermsSupport: DictionaryTermsSupport { .supported }

    var dictionaryTermsBudget: DictionaryTermsBudget {
        DictionaryTermsBudget(maxTerms: 5000)
    }

    func transcribe(
        audio: AudioData,
        language: String?,
        translate: Bool,
        prompt: String?,
        dictionaryTermHints: [PluginDictionaryTermHint]
    ) async throws -> PluginTranscriptionResult {
        guard !translate else {
            throw PluginTranscriptionError.apiError("ByteDance Seed ASR does not support translation.")
        }
        let snap = state.snapshot()
        guard let apiKey = snap.apiKey, !apiKey.isEmpty else {
            throw PluginTranscriptionError.notConfigured
        }
        guard !audio.wavData.isEmpty else {
            throw PluginTranscriptionError.apiError("Empty audio data")
        }

        // Normalize + clip terms to our declared budget.
        let clipped = PluginDictionaryTerms.clippedTermHints(
            from: dictionaryTermHints,
            budget: dictionaryTermsBudget
        )
        let hotwords = clipped.map(\.text)

        let transcript = try await Self.runSeedASR(
            wavData: audio.wavData,
            apiKey: apiKey,
            hotwords: hotwords
        )
        return PluginTranscriptionResult(text: transcript)
    }

    // MARK: - Settings helpers (used by the plugin's combined settings view)

    func snapshotCredentials() -> String? {
        state.snapshot().apiKey
    }

    func setApiKey(_ apiKey: String) throws {
        guard let host = state.currentHost() else {
            throw ByteDanceSeedASRConfigurationError.missingHost
        }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try host.storeSecret(key: Self.apiKeySecretKey, value: trimmed)
            state.update(apiKey: trimmed)
            host.notifyCapabilitiesChanged()
        } catch {
            logger.error("Failed to store ByteDance API key: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Seed-ASR WebSocket protocol

    private static func runSeedASR(
        wavData: Data,
        apiKey: String,
        hotwords: [String] = []
    ) async throws -> String {
        guard let url = URL(string: Self.endpoint) else {
            throw PluginTranscriptionError.networkError("Invalid URL: \(Self.endpoint)")
        }

        // Auth + framing headers (single modern API key).
        var request = URLRequest(url: url)
        request.setValue(Self.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = Self.resourceTimeout
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        do {
            // 1. Full client request (gzipped JSON config).
            let payload = try Self.requestPayload(wavData: wavData, hotwords: hotwords)
            try await task.send(.data(try Self.fullRequestFrame(payload: payload)))

            // 2. Wait for the server ack.
            _ = try await Self.nextResponse(task)

            // 3. Stream the WAV as audio-only frames (seq from 2).
            let (segments, _) = try WAV.segments(wavData: wavData, segmentDurationMs: Self.segmentDurationMs)
            var seq = 2
            for (index, segment) in segments.enumerated() {
                let isLast = index == segments.count - 1
                try await task.send(.data(try Self.audioFrame(segment: segment, seq: seq, isLast: isLast)))
                seq += 1
            }

            // 4. Read responses until the final package.
            var transcript = ""
            var code = 0
            while true {
                let response = try await Self.nextResponse(task)
                code = response.code
                if !response.text.isEmpty { transcript = response.text }
                if response.isLast || response.code != 0 { break }
            }

            guard code == 0 else {
                throw PluginTranscriptionError.apiError("Seed-ASR error code \(code)")
            }
            let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                throw PluginTranscriptionError.apiError("No transcript returned")
            }
            return cleaned
        } catch let error as PluginTranscriptionError {
            throw error
        } catch {
            throw PluginTranscriptionError.networkError("Seed-ASR request failed: \(error.localizedDescription)")
        }
    }

    private static func nextResponse(
        _ task: URLSessionWebSocketTask
    ) async throws -> (code: Int, isLast: Bool, text: String) {
        let message = try await task.receive()
        guard case .data(let data) = message else {
            throw PluginTranscriptionError.networkError("Unexpected WebSocket message")
        }
        return try parseResponse(data)
    }

    // MARK: - Request payload

    private static func requestPayload(wavData: Data, hotwords: [String]) throws -> Data {
        let info = try WAV.parse(wavData)
        var request: [String: Any] = [
            "model_name": "bigmodel",
            "enable_itn": true,
            "enable_punc": true,
            "enable_ddc": true,
            // enable_auto_lang=false: auto-lang can misclassify non-native English
            // as "Chinese English" and switch to CJK punctuation (。，) and drop
            // sentence capitalization. Disabling it yields proper ASCII punctuation
            // + capitalization for English, while Chinese output is unaffected.
            // (Only correct when not switching languages mid-sentence.)
            "enable_auto_lang": false,
            "show_utterances": false,
            "enable_nonstream": false,
        ]
        if !hotwords.isEmpty {
            // Seed direct hotwords: `request.corpus.context` is a JSON *string*
            // containing `{"hotwords":[{"word":...}]}`. nostream supports up to
            // 5000 words, and directly-supplied hotwords take priority over any
            // server-side hotword table.
            let hotwordsObject = ["hotwords": hotwords.map { ["word": $0] }]
            let hotwordsJson = String(
                data: try JSONSerialization.data(withJSONObject: hotwordsObject),
                encoding: .utf8
            ) ?? "{}"
            request["corpus"] = ["context": hotwordsJson]
        }
        let body: [String: Any] = [
            "user": ["uid": "typewhisper"],
            "audio": [
                "format": "wav",
                "codec": "raw",
                "rate": info.rate,
                "bits": info.bits,
                "channel": info.channels,
            ],
            "request": request,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Framing

    private static func fullRequestFrame(payload: Data) throws -> Data {
        let compressed = try Gzip.encode(payload)
        var out = Data([0x11, 0x11, 0x11, 0x00])   // V1 / CLIENT_FULL_REQUEST+POS_SEQUENCE / JSON+GZIP
        out.append(bigEndianInt32(1))
        out.append(bigEndianUInt32(UInt32(compressed.count)))
        out.append(compressed)
        return out
    }

    private static func audioFrame(segment: Data, seq: Int, isLast: Bool) throws -> Data {
        let compressed = try Gzip.encode(segment)
        var out: Data
        if isLast {
            out = Data([0x11, 0x23, 0x11, 0x00])   // CLIENT_AUDIO_ONLY_REQUEST + NEG_WITH_SEQUENCE
        } else {
            out = Data([0x11, 0x21, 0x11, 0x00])   // CLIENT_AUDIO_ONLY_REQUEST + POS_SEQUENCE
        }
        let seqValue = isLast ? -seq : seq
        out.append(bigEndianInt32(Int32(seqValue)))
        out.append(bigEndianUInt32(UInt32(compressed.count)))
        out.append(compressed)
        return out
    }

    private static func bigEndianInt32(_ value: Int32) -> Data {
        var v = value.bigEndian
        return withUnsafeBytes(of: &v) { Data($0) }
    }

    private static func bigEndianUInt32(_ value: UInt32) -> Data {
        var v = value.bigEndian
        return withUnsafeBytes(of: &v) { Data($0) }
    }

    // MARK: - Response parsing

    private static func parseResponse(_ data: Data) throws -> (code: Int, isLast: Bool, text: String) {
        guard data.count >= 4 else {
            throw PluginTranscriptionError.networkError("Malformed response")
        }
        let headerSize = Int(data[0] & 0x0f)
        let messageType = (data[1] >> 4) & 0x0f
        let flags = data[1] & 0x0f
        let compression = data[2] & 0x0f

        var offset = headerSize * 4
        if flags & 0x01 != 0 { offset += 4 } // payload_sequence
        let isLast = flags & 0x02 != 0
        if flags & 0x04 != 0 { offset += 4 } // event

        var code = 0
        if messageType == 0x9 {              // SERVER_FULL_RESPONSE
            offset += 4                       // payload_size
        } else if messageType == 0xF {        // SERVER_ERROR_RESPONSE
            guard data.count >= offset + 8 else {
                throw PluginTranscriptionError.networkError("Malformed error response")
            }
            code = Int(bigEndianInt32(at: data, offset: offset))
            offset += 8
        }

        guard offset <= data.count else {
            throw PluginTranscriptionError.networkError("Malformed response")
        }
        var payload = data.subdata(in: offset..<data.count)

        if compression == 1 {
            do {
                payload = try Gzip.decode(payload)
            } catch {
                throw PluginTranscriptionError.networkError("Failed to decompress response")
            }
        }

        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let text = result["text"] as? String else {
            return (code, isLast, "")
        }
        return (code, isLast, text)
    }

    private static func bigEndianInt32(at data: Data, offset: Int) -> Int32 {
        var value: Int32 = 0
        for i in 0..<4 where offset + i < data.count {
            value = (value << 8) | Int32(data[offset + i])
        }
        return value
    }

    // MARK: - Gzip helpers (see Support/Gzip.swift)
}

// MARK: - State

private struct ByteDanceSeedASRSnapshot: Sendable {
    let apiKey: String?
}

private final class ByteDanceSeedASRState: @unchecked Sendable {
    private let lock = NSLock()
    private var host: HostServices?
    private var apiKey: String?

    func activate(host: HostServices, apiKey: String?) {
        lock.withLock {
            self.host = host
            self.apiKey = apiKey
        }
    }

    func deactivate() {
        lock.withLock { host = nil }
    }

    func currentHost() -> HostServices? {
        lock.withLock { host }
    }

    func snapshot() -> ByteDanceSeedASRSnapshot {
        lock.withLock { ByteDanceSeedASRSnapshot(apiKey: apiKey) }
    }

    func update(apiKey: String?) {
        lock.withLock { self.apiKey = apiKey }
    }
}

// MARK: - Errors

private enum ByteDanceSeedASRConfigurationError: LocalizedError {
    case missingHost

    var errorDescription: String? {
        switch self {
        case .missingHost:
            "Plugin is not active."
        }
    }
}
