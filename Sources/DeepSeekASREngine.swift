import Foundation
import os
import TypeWhisperPluginSDK

/// TypeWhisper transcription engine backed by DeepSeek's speech-to-text API.
///
/// Pipeline: TypeWhisper AudioData -> 16 kHz WAV as multipart `file` ->
/// `POST /v1/tools/asr` -> `text` -> transcript.
///
/// The API takes no options: language is auto-detected and there is no
/// model, prompt, or hotword field (unknown fields are silently ignored), so
/// dictionary Terms are not forwarded and Corrections stay host-side.
@objc(DeepSeekASREngine)
final class DeepSeekASREngine: NSObject, TranscriptionEnginePlugin, @unchecked Sendable {
    static let pluginId = TypeWhisperCNProvidersPlugin.pluginId
    static let pluginName = TypeWhisperCNProvidersPlugin.pluginName

    private static let endpoint = "https://api.deepseek.com/v1/tools/asr"
    private static let modelId = "deepseek-asr"
    private static let secretKey = "deepseekApiKey"
    private static let requestTimeout: TimeInterval = 30

    private let state = DeepSeekASRState()
    private let logger = Logger(subsystem: "dev.yfzhou.typewhisper-cn-providers", category: "DeepSeekASR")

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

    var providerId: String { "deepseek-asr" }
    var providerDisplayName: String { "DeepSeek ASR" }

    var isConfigured: Bool {
        guard let key = state.snapshot().apiKey else { return false }
        return !key.isEmpty
    }

    var transcriptionModels: [PluginModelInfo] {
        [PluginModelInfo(id: Self.modelId, displayName: "DeepSeek ASR")]
    }

    var selectedModelId: String? { Self.modelId }
    func selectModel(_ modelId: String) {}

    var supportsTranslation: Bool { false }

    /// Language is always auto-detected server-side.
    var supportedLanguages: [String] { ["auto"] }

    func transcribe(
        audio: AudioData,
        language: String?,
        translate: Bool,
        prompt: String?
    ) async throws -> PluginTranscriptionResult {
        guard !translate else {
            throw PluginTranscriptionError.apiError("DeepSeek ASR does not support translation.")
        }
        guard let apiKey = state.snapshot().apiKey, !apiKey.isEmpty else {
            throw PluginTranscriptionError.notConfigured
        }

        let request = try Self.makeRequest(wavData: audio.wavData, apiKey: apiKey)
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
            throw DeepSeekASRConfigurationError.missingHost
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try host.storeSecret(key: Self.secretKey, value: trimmed)
            state.updateApiKey(trimmed)
            host.notifyCapabilitiesChanged()
        } catch {
            logger.error("Failed to store DeepSeek API key: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Request / Response

    private static func makeRequest(wavData: Data, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: Self.endpoint) else {
            throw PluginTranscriptionError.networkError("Invalid URL: \(Self.endpoint)")
        }
        guard !wavData.isEmpty else {
            throw PluginTranscriptionError.apiError("Empty audio data")
        }

        let boundary = "TypeWhisper-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wavData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
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

    /// Server-side limits (e.g. audio over 120 s) are relayed from here as-is.
    /// Errors use the OpenAI shape: `{"error":{"message":...,"type":...,"code":...}}`.
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
        struct ResponseBody: Decodable {
            let text: String?
        }

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            // Silence comes back as HTTP 200 with empty text.
            let cleaned = (decoded.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                throw PluginTranscriptionError.apiError("No transcript returned")
            }
            return PluginTranscriptionResult(text: cleaned)
        } catch let error as PluginTranscriptionError {
            throw error
        } catch {
            throw PluginTranscriptionError.apiError("Failed to parse response: \(error.localizedDescription)")
        }
    }
}

// MARK: - State

private struct DeepSeekASRSnapshot: Sendable {
    let apiKey: String?
}

private final class DeepSeekASRState: @unchecked Sendable {
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

    func snapshot() -> DeepSeekASRSnapshot {
        lock.withLock { DeepSeekASRSnapshot(apiKey: apiKey) }
    }

    func updateApiKey(_ apiKey: String?) {
        lock.withLock { self.apiKey = apiKey }
    }
}

// MARK: - Errors

private enum DeepSeekASRConfigurationError: LocalizedError {
    case missingHost

    var errorDescription: String? {
        switch self {
        case .missingHost:
            "Plugin is not active."
        }
    }
}
