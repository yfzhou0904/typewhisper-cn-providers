import Foundation
import os
import TypeWhisperPluginSDK

/// TypeWhisper transcription engine backed by Xiaomi's China-hosted
/// `mimo-v2.5-asr` API.
///
/// Pipeline: TypeWhisper AudioData -> base64 WAV -> MiMo chat-completions
/// `input_audio` request -> `choices[0].message.content` -> transcript.
@objc(XiaomiMiMoASREngine)
final class XiaomiMiMoASREngine: NSObject, TranscriptionEnginePlugin, @unchecked Sendable {
    static let pluginId = TypeWhisperCNProvidersPlugin.pluginId
    static let pluginName = TypeWhisperCNProvidersPlugin.pluginName

    private static let endpoint = "https://api.xiaomimimo.com/v1/chat/completions"
    private static let modelId = "mimo-v2.5-asr"
    private static let secretKey = "apiKey"
    private static let requestTimeout: TimeInterval = 30

    private let state = MiMoASRState()
    private let logger = Logger(subsystem: "dev.yfzhou.typewhisper-cn-providers", category: "Plugin")

    required override init() {
        super.init()
    }

    func activate(host: HostServices) {
        state.activate(host: host, apiKey: host.loadSecret(key: Self.secretKey))
    }

    func deactivate() {
        state.deactivate()
    }

    // MARK: - TranscriptionEnginePlugin

    var providerId: String { "mimo-asr" }
    var providerDisplayName: String { "Xiaomi MiMo ASR" }

    var isConfigured: Bool {
        guard let key = state.snapshot().apiKey else { return false }
        return !key.isEmpty
    }

    var transcriptionModels: [PluginModelInfo] {
        [PluginModelInfo(id: Self.modelId, displayName: Self.modelId)]
    }

    var selectedModelId: String? { Self.modelId }
    func selectModel(_ modelId: String) {}

    var supportsTranslation: Bool { false }

    var supportedLanguages: [String] { ["auto", "zh", "en"] }

    func transcribe(
        audio: AudioData,
        language: String?,
        translate: Bool,
        prompt: String?
    ) async throws -> PluginTranscriptionResult {
        guard !translate else {
            throw PluginTranscriptionError.apiError("Xiaomi MiMo ASR does not support translation.")
        }
        guard let apiKey = state.snapshot().apiKey, !apiKey.isEmpty else {
            throw PluginTranscriptionError.notConfigured
        }

        let request = try Self.makeRequest(
            wavData: audio.wavData,
            apiKey: apiKey,
            requestedLanguage: language
        )

        let (data, response) = try await PluginHTTPClient.data(for: request)
        try Self.validateHTTPResponse(data: data, response: response)
        return try Self.parseResponse(data)
    }

    // MARK: - Settings helpers

    func snapshotCredentials() -> String? {
        state.snapshot().apiKey
    }

    func setApiKey(_ key: String) throws {
        guard let host = state.currentHost() else {
            throw MiMoASRConfigurationError.missingHost
        }
        do {
            try host.storeSecret(key: Self.secretKey, value: key)
            state.updateApiKey(key)
            host.notifyCapabilitiesChanged()
        } catch {
            logger.error("Failed to store API key: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Request / Response

    private static func makeRequest(
        wavData: Data,
        apiKey: String,
        requestedLanguage: String?
    ) throws -> URLRequest {
        guard let url = URL(string: Self.endpoint) else {
            throw PluginTranscriptionError.networkError("Invalid URL: \(Self.endpoint)")
        }
        guard !wavData.isEmpty else {
            throw PluginTranscriptionError.apiError("Empty audio data")
        }

        let base64 = wavData.base64EncodedString()
        let dataURI = "data:audio/wav;base64,\(base64)"
        let language = Self.normalizedLanguage(requestedLanguage)

        struct InputAudio: Encodable {
            let data: String
        }
        struct ContentItem: Encodable {
            let type: String
            let input_audio: InputAudio
        }
        struct Message: Encodable {
            let role: String
            let content: [ContentItem]
        }
        struct ASROptions: Encodable {
            let language: String
        }
        struct RequestBody: Encodable {
            let model: String
            let messages: [Message]
            let asr_options: ASROptions
        }

        let body = RequestBody(
            model: Self.modelId,
            messages: [
                Message(
                    role: "user",
                    content: [ContentItem(type: "input_audio", input_audio: InputAudio(data: dataURI))]
                )
            ],
            asr_options: ASROptions(language: language)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Map TypeWhisper language values to MiMo-supported ones. Anything outside
    /// {zh, en} (including nil / "auto") is sent as "auto".
    private static func normalizedLanguage(_ language: String?) -> String {
        guard let language, !language.isEmpty else { return "auto" }
        let lower = language.lowercased()
        if lower.hasPrefix("zh") { return "zh" }
        if lower.hasPrefix("en") { return "en" }
        return "auto"
    }

    private static func validateHTTPResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PluginTranscriptionError.networkError("Invalid response")
        }

        switch http.statusCode {
        case 200:
            return
        case 401, 403:
            throw PluginTranscriptionError.invalidApiKey
        case 429:
            throw PluginTranscriptionError.rateLimited
        default:
            let message = Self.errorMessage(from: data)
                ?? "HTTP \(http.statusCode)"
            throw PluginTranscriptionError.apiError(message)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return String(data: data, encoding: .utf8).map { $0.isEmpty ? nil : $0 } ?? nil
        }
        if let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let code = error["code"] {
            return "\(code)"
        }
        return nil
    }

    private static func parseResponse(_ data: Data) throws -> PluginTranscriptionResult {
        struct Message: Decodable {
            let content: String?
        }
        struct Choice: Decodable {
            let message: Message
        }
        struct ResponseBody: Decodable {
            let choices: [Choice]?
        }

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            guard let transcript = decoded.choices?.first?.message.content,
                  !transcript.isEmpty else {
                throw PluginTranscriptionError.apiError("No transcript in response")
            }
            let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            return PluginTranscriptionResult(text: cleaned)
        } catch let error as PluginTranscriptionError {
            throw error
        } catch {
            throw PluginTranscriptionError.apiError("Failed to parse response: \(error.localizedDescription)")
        }
    }
}

// MARK: - State

private struct MiMoASRSnapshot: Sendable {
    let apiKey: String?
}

private final class MiMoASRState: @unchecked Sendable {
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

    func snapshot() -> MiMoASRSnapshot {
        lock.withLock { MiMoASRSnapshot(apiKey: apiKey) }
    }

    func updateApiKey(_ apiKey: String?) {
        lock.withLock { self.apiKey = apiKey }
    }
}

// MARK: - Errors

private enum MiMoASRConfigurationError: LocalizedError {
    case missingHost

    var errorDescription: String? {
        switch self {
        case .missingHost:
            "Plugin is not active."
        }
    }
}

