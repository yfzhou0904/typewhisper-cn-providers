import Foundation
import SwiftUI
import TypeWhisperPluginSDK

/// Registers Xiaomi MiMo as the primary engine and ByteDance Seed as an
/// additional selectable engine (standard and Agent Plan), with shared lifecycle.
@objc(TypeWhisperCNProvidersPlugin)
final class TypeWhisperCNProvidersPlugin: NSObject, TranscriptionEnginePlugin, AdditionalTranscriptionEnginesProviding, @unchecked Sendable {
    static let pluginId = "dev.yfzhou.typewhisper-cn-providers"
    static let pluginName = "CN Providers"

    private let mimoEngine = XiaomiMiMoASREngine()
    private let seedEngine = ByteDanceSeedASREngine()
    private let agentPlanEngine = ByteDanceSeedASREngine(service: .agentPlan)

    required override init() {
        super.init()
    }

    func activate(host: HostServices) {
        mimoEngine.activate(host: host)
        seedEngine.activate(host: host)
        agentPlanEngine.activate(host: host)
    }

    func deactivate() {
        mimoEngine.deactivate()
        seedEngine.deactivate()
        agentPlanEngine.deactivate()
    }

    // MARK: - AdditionalTranscriptionEnginesProviding

    var additionalTranscriptionEngines: [any TranscriptionEnginePlugin] {
        [seedEngine, agentPlanEngine]
    }

    // MARK: - Primary engine (Xiaomi MiMo)

    var providerId: String { mimoEngine.providerId }
    var providerDisplayName: String { mimoEngine.providerDisplayName }
    var isConfigured: Bool { mimoEngine.isConfigured }
    var transcriptionModels: [PluginModelInfo] { mimoEngine.transcriptionModels }
    var selectedModelId: String? { mimoEngine.selectedModelId }

    func selectModel(_ modelId: String) {
        mimoEngine.selectModel(modelId)
    }

    var supportsTranslation: Bool { mimoEngine.supportsTranslation }
    var supportedLanguages: [String] { mimoEngine.supportedLanguages }

    func transcribe(
        audio: AudioData,
        language: String?,
        translate: Bool,
        prompt: String?
    ) async throws -> PluginTranscriptionResult {
        try await mimoEngine.transcribe(
            audio: audio,
            language: language,
            translate: translate,
            prompt: prompt
        )
    }

    // MARK: - Combined settings

    var settingsView: AnyView? {
        AnyView(CNProvidersSettingsView(
            mimoEngine: mimoEngine, seedEngine: seedEngine, agentPlanEngine: agentPlanEngine
        ))
    }
}
