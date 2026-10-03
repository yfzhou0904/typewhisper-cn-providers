import Foundation
import SwiftUI

struct CNProvidersSettingsView: View {
    let mimoEngine: XiaomiMiMoASREngine
    let seedEngine: ByteDanceSeedASREngine
    private let bundle = pluginModuleBundle

    @State private var apiKeyInput = ""
    @State private var showApiKey = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Xiaomi MiMo ASR", bundle: bundle)
                    .font(.headline)

                Text("Transcription via Xiaomi's China-hosted mimo-v2.5-asr API. Language defaults to auto (Chinese/English mixed).", bundle: bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("MiMo API Key", bundle: bundle)
                    .font(.headline)

                HStack(spacing: 8) {
                    if showApiKey {
                        TextField(String(localized: "MiMo API Key", bundle: bundle), text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField(String(localized: "MiMo API Key", bundle: bundle), text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showApiKey.toggle()
                    } label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Text("Stored securely in the macOS Keychain.", bundle: bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    save()
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

            Divider()
                .padding(.vertical, 4)

            ByteDanceSeedASRSettingsSection(seedEngine: seedEngine)

            Text("All credentials are stored securely in the macOS Keychain.", bundle: bundle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear {
            apiKeyInput = mimoEngine.snapshotCredentials() ?? ""
        }
    }

    private func save() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try mimoEngine.setApiKey(trimmed)
            saved = true
        } catch {
            saved = false
        }
    }
}

private struct ByteDanceSeedASRSettingsSection: View {
    let seedEngine: ByteDanceSeedASREngine
    private let bundle = pluginModuleBundle

    @State private var apiKeyInput = ""
    @State private var showKey = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ByteDance Seed ASR", bundle: bundle)
                    .font(.headline)

                Text("Transcription via ByteDance's Seed-ASR 2.0 bigmodel service. Auto-detects Chinese/English with punctuation.", bundle: bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key", bundle: bundle)
                    .font(.subheadline)

                HStack(spacing: 8) {
                    if showKey {
                        TextField(String(localized: "Seed ASR API Key", bundle: bundle), text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField(String(localized: "Seed ASR API Key", bundle: bundle), text: $apiKeyInput)
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
                    save()
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
            apiKeyInput = seedEngine.snapshotCredentials() ?? ""
        }
    }

    private func save() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try seedEngine.setApiKey(key)
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
