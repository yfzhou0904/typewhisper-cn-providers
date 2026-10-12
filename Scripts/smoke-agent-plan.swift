import Foundation
import TypeWhisperPluginSDK

/// Uses the plugin's actual WAV, gzip, framing, and response handling code.
@main
struct AgentPlanSmokeTest {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let audioPath = arguments.first else {
                throw SmokeError(message: "Usage: Scripts/smoke-agent-plan.sh <16-bit PCM WAV> [hotword ...]")
            }
            let apiKey = try loadAPIKey()
            let audio = try Data(contentsOf: URL(fileURLWithPath: audioPath))
            let info = try WAV.parse(audio)
            guard info.bits == 16, info.channels == 1, info.rate == 16000 else {
                throw SmokeError(message: "Use a 16 kHz, mono, 16-bit PCM WAV file.")
            }
            let service = ByteDanceSeedASREngine.Service.agentPlan
            let (plugin, engine) = try configuredPlugin(apiKey: apiKey)
            defer { plugin.deactivate() }
            print("PASS: provider registration and independent credential save/reload")
            print("Endpoint: \(service.endpoint)")
            print("Resource: volc.seedasr.sauc.duration")
            print("Audio: \(audio.count) bytes; hotwords: \(arguments.dropFirst().count)")
            let start = Date()
            let result = try await engine.transcribe(
                audio: AudioData(samples: [], wavData: audio, duration: Double(audio.count - 44) / 32000),
                language: nil,
                translate: false,
                prompt: nil,
                dictionaryTermHints: arguments.dropFirst().map { PluginDictionaryTermHint(text: $0) }
            )
            print("Transcript: \(result.text)")
            print(String(format: "PASS (%.2f seconds)", Date().timeIntervalSince(start)))
        } catch {
            // Never print credentials or request headers.
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func configuredPlugin(apiKey: String) throws -> (TypeWhisperCNProvidersPlugin, ByteDanceSeedASREngine) {
        // Exercises the real plugin lifecycle/settings without writing to Keychain.
        let host = SmokeHost()
        let plugin = TypeWhisperCNProvidersPlugin()
        plugin.activate(host: host)
        let engines = plugin.additionalTranscriptionEngines.compactMap { $0 as? ByteDanceSeedASREngine }
        guard plugin.providerId == "mimo-asr", engines.count == 2,
              let standard = engines.first(where: { $0.providerId == "bytedance-seed-asr" }),
              let plan = engines.first(where: { $0.providerId == "volcengine-agent-plan-asr" }),
              standard.isConfigured, !plan.isConfigured else {
            throw SmokeError(message: "Provider registration or credential isolation failed.")
        }
        try plan.setApiKey(" \(apiKey)\n")
        guard plan.isConfigured, host.loadSecret(key: "arkAgentPlanApiKey") == apiKey,
              standard.snapshotCredentials() == "standard-placeholder" else {
            throw SmokeError(message: "Independent credential saving failed.")
        }
        plugin.deactivate()
        plugin.activate(host: host)
        guard plan.snapshotCredentials() == apiKey,
              standard.snapshotCredentials() == "standard-placeholder" else {
            throw SmokeError(message: "Independent credential reload failed.")
        }
        return (plugin, plan)
    }

    private static func loadAPIKey() throws -> String {
        if let key = ProcessInfo.processInfo.environment["ARK_API_KEY"],
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Read simple dotenv assignments as data, without evaluating shell code.
        if let dotenv = try? String(contentsOfFile: ".env", encoding: .utf8) {
            for line in dotenv.components(separatedBy: .newlines) {
                var assignment = line.trimmingCharacters(in: .whitespaces)
                if assignment.hasPrefix("export ") { assignment.removeFirst(7) }
                let parts = assignment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "ARK_API_KEY" else { continue }
                var key = parts[1].trimmingCharacters(in: .whitespaces)
                if key.count >= 2, (key.first == "\"" && key.last == "\""
                    || key.first == "'" && key.last == "'") {
                    key.removeFirst()
                    key.removeLast()
                }
                if !key.isEmpty { return key }
            }
        }
        throw SmokeError(message: "Set ARK_API_KEY in the environment or repository .env.")
    }
}

private struct SmokeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class SmokeHost: HostServices, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets = ["bdApiKey": "standard-placeholder"]
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
