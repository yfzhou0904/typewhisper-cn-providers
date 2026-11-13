import Foundation
import TypeWhisperPluginSDK

/// Uses the plugin's actual multipart request and response handling code.
@main
struct DeepSeekSmokeTest {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let audioPath = arguments.first else {
                throw SmokeError(message: "Usage: Scripts/smoke-deepseek.sh <16-bit PCM WAV>")
            }
            let apiKey = try loadAPIKey()
            let audio = try Data(contentsOf: URL(fileURLWithPath: audioPath))
            let info = try WAV.parse(audio)
            guard info.bits == 16, info.channels == 1, info.rate == 16000 else {
                throw SmokeError(message: "Use a 16 kHz, mono, 16-bit PCM WAV file.")
            }
            let (plugin, engine) = try configuredPlugin(apiKey: apiKey)
            defer { plugin.deactivate() }
            print("PASS: provider registration and independent credential save/reload")
            print("Audio: \(audio.count) bytes")
            let start = Date()
            let result = try await engine.transcribe(
                audio: AudioData(samples: [], wavData: audio, duration: Double(audio.count - 44) / 32000),
                language: nil,
                translate: false,
                prompt: nil
            )
            print("Transcript: \(result.text)")
            print(String(format: "PASS (%.2f seconds)", Date().timeIntervalSince(start)))
        } catch {
            // Never print credentials or request headers.
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func configuredPlugin(apiKey: String) throws -> (TypeWhisperCNProvidersPlugin, DeepSeekASREngine) {
        // Exercises the real plugin lifecycle/settings without writing to Keychain.
        let host = SmokeHost()
        let plugin = TypeWhisperCNProvidersPlugin()
        plugin.activate(host: host)
        let engines = plugin.additionalTranscriptionEngines.compactMap { $0 as? DeepSeekASREngine }
        guard plugin.providerId == "mimo-asr", engines.count == 1,
              let engine = engines.first, engine.providerId == "deepseek-asr",
              !engine.isConfigured, plugin.isConfigured else {
            throw SmokeError(message: "Provider registration or credential isolation failed.")
        }
        try engine.setApiKey(" \(apiKey)\n")
        guard engine.isConfigured, host.loadSecret(key: "deepseekApiKey") == apiKey,
              host.loadSecret(key: "apiKey") == "mimo-placeholder" else {
            throw SmokeError(message: "Independent credential saving failed.")
        }
        plugin.deactivate()
        plugin.activate(host: host)
        guard engine.snapshotCredentials() == apiKey,
              plugin.isConfigured, host.loadSecret(key: "apiKey") == "mimo-placeholder" else {
            throw SmokeError(message: "Independent credential reload failed.")
        }
        return (plugin, engine)
    }

    private static func loadAPIKey() throws -> String {
        if let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"],
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Read simple dotenv assignments as data, without evaluating shell code.
        if let dotenv = try? String(contentsOfFile: ".env", encoding: .utf8) {
            for line in dotenv.components(separatedBy: .newlines) {
                var assignment = line.trimmingCharacters(in: .whitespaces)
                if assignment.hasPrefix("export ") { assignment.removeFirst(7) }
                let parts = assignment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "DEEPSEEK_API_KEY" else { continue }
                var key = parts[1].trimmingCharacters(in: .whitespaces)
                if key.count >= 2, (key.first == "\"" && key.last == "\""
                    || key.first == "'" && key.last == "'") {
                    key.removeFirst()
                    key.removeLast()
                }
                if !key.isEmpty { return key }
            }
        }
        throw SmokeError(message: "Set DEEPSEEK_API_KEY in the environment or repository .env.")
    }
}

private struct SmokeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class SmokeHost: HostServices, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets = ["apiKey": "mimo-placeholder"]
    func storeSecret(key: String, value: String) throws {
        lock.withLock { secrets[key] = value }
    }
    func loadSecret(key: String) -> String? { lock.withLock { secrets[key] } }
    func userDefault(forKey: String) -> Any? { nil }
    func setUserDefault(_ value: Any?, forKey: String) {}
    var pluginDataDirectory: URL { URL(fileURLWithPath: "build") }
    var activeAppBundleId: String? { nil }
    var activeAppName: String? { nil }
    let eventBus: EventBusProtocol = SmokeEventBus()
    var availableRuleNames: [String] { [] }
    func notifyCapabilitiesChanged() {}
    func setStreamingDisplayActive(_ active: Bool) {}
}

private struct SmokeEventBus: EventBusProtocol {
    func subscribe(handler: @escaping @Sendable (TypeWhisperEvent) async -> Void) -> UUID { UUID() }
    func unsubscribe(id: UUID) {}
}
