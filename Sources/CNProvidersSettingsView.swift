import Foundation
import SwiftUI

struct CNProvidersSettingsView: View {
    let mimoEngine: XiaomiMiMoASREngine
    let seedEngine: ByteDanceSeedASREngine
    let agentPlanEngine: ByteDanceSeedASREngine
    let deepSeekEngine: DeepSeekASREngine
    private let bundle = pluginModuleBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            APIKeySettingsSection(
                title: mimoEngine.providerDisplayName,
                caption: "Transcription via Xiaomi's China-hosted mimo-v2.5-asr API. Language defaults to auto (Chinese/English mixed).",
                keyLabel: "MiMo API Key",
                load: { mimoEngine.snapshotCredentials() },
                save: { try mimoEngine.setApiKey($0) }
            )

            Divider()
                .padding(.vertical, 4)

            seedSection(seedEngine)

            Divider()
                .padding(.vertical, 4)

            seedSection(agentPlanEngine)

            Divider()
                .padding(.vertical, 4)

            APIKeySettingsSection(
                title: deepSeekEngine.providerDisplayName,
                caption: "Transcription via DeepSeek's speech-to-text API. Language is auto-detected; recordings are limited to 2 minutes. Dictionary Terms are not supported.",
                keyLabel: "DeepSeek API Key",
                load: { deepSeekEngine.snapshotCredentials() },
                save: { try deepSeekEngine.setApiKey($0) }
            )

            Text("All credentials are stored securely in the macOS Keychain.", bundle: bundle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func seedSection(_ engine: ByteDanceSeedASREngine) -> APIKeySettingsSection {
        APIKeySettingsSection(
            title: engine.providerDisplayName,
            caption: engine.service == .agentPlan
                ? "Uses your dedicated Agent Plan API key and subscription credits for Seed-ASR 2.0."
                : "Transcription via ByteDance's Seed-ASR 2.0 bigmodel service. Auto-detects Chinese/English with punctuation.",
            keyLabel: engine.service == .agentPlan ? "Agent Plan API Key" : "Seed ASR API Key",
            load: { engine.snapshotCredentials() },
            save: { try engine.setApiKey($0) }
        )
    }
}

/// One provider's description plus a Keychain-backed API key field.
private struct APIKeySettingsSection: View {
    let title: String
    let caption: String
    let keyLabel: String
    let load: () -> String?
    let save: (String) throws -> Void
    private let bundle = pluginModuleBundle

    @State private var apiKeyInput = ""
    @State private var showKey = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(keyLabel)
                    .font(.subheadline)

                HStack(spacing: 8) {
                    if showKey {
                        TextField(keyLabel, text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField(keyLabel, text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Text("Stored securely in the macOS Keychain.", bundle: bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    commit()
                } label: {
                    Text("Save", bundle: bundle)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if saved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Saved", bundle: bundle)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .onAppear {
            apiKeyInput = load() ?? ""
        }
    }

    private func commit() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try save(key)
            saved = true
        } catch {
            saved = false
        }
    }
}

private let pluginModuleBundle: Bundle = {
#if SWIFT_PACKAGE
    Bundle.module
#else
    Bundle(for: TypeWhisperCNProvidersPlugin.self)
#endif
}()
