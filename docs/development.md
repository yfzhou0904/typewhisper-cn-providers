# Development

Build with full Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
./Scripts/build.sh
# Install a symlink for local development:
./Scripts/build.sh --symlink
```

Restart TypeWhisper after rebuilding. The bundle is produced at `build/DerivedData/Build/Products/Release/TypeWhisperCNProviders.bundle`.

`project.yml` defines the build. The script regenerates the Xcode project, embeds the vendored SDK framework, and ad-hoc signs the bundle.

## Implementation

- `Sources/TypeWhisperCNProvidersPlugin.swift` registers providers and forwards the primary engine to MiMo.
- `Sources/XiaomiMiMoASREngine.swift` handles MiMo HTTPS requests.
- `Sources/ByteDanceSeedASREngine.swift` handles both standard Seed and Agent Plan WebSocket requests.
- `Sources/CNProvidersSettingsView.swift` provides credential settings.
- `Sources/Support/` contains WAV parsing and gzip framing.

All providers implement recorded-audio transcription without streaming partials or translation. Seed providers forward dictionary Terms as hotwords; MiMo relies on host-side Corrections. See the [API reference](API.md) for protocol details and tuning.

## Agent Plan smoke test

Build with `./Scripts/build.sh`. Set `ARK_API_KEY` in your environment or a local `.env` (gitignored), then run against a short 16 kHz mono 16-bit PCM WAV:

```bash
say -v Tingting -o build/agent-plan.aiff '你好，这是火山引擎语音识别测试。'
afconvert -f WAVE -d LEI16@16000 -c 1 build/agent-plan.aiff build/agent-plan.wav
./Scripts/smoke-agent-plan.sh build/agent-plan.wav
# Optional dictionary hotwords:
./Scripts/smoke-agent-plan.sh build/agent-plan.wav 火山引擎
```

This makes a real Agent Plan request and consumes credits. It compiles the plugin's actual transport code and prints the transcript and elapsed time. It never falls back to the standard paid endpoint.


The test also checks provider registration and independent credential save/reload using an in-memory host. It does not write credentials to the macOS Keychain.

## Build verification

```bash
codesign --verify --deep --strict build/DerivedData/Build/Products/Release/TypeWhisperCNProviders.bundle
git diff --check
```
