# TypeWhisper CN Providers — China-hosted transcription providers for TypeWhisper

A [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) transcription plugin that brings **independently selectable cloud ASR providers** to push-to-talk dictation, hosted in China. Supports pay-as-you-go providers and a Volcengine Agent Plan subscription. Currently ships:

1. **Xiaomi MiMo-V2.5-ASR** — OpenAI-compatible chat-completions API (`providerId = "mimo-asr"`)
2. **ByteDance Seed-ASR 2.0** — Volcengine `bigmodel` WebSocket API (`providerId = "bytedance-seed-asr"`)
3. **Volcengine Agent Plan ASR** — Seed-ASR 2.0 through the dedicated subscription endpoint (`providerId = "volcengine-agent-plan-asr"`)

Switch engines live, in-app, via **Settings → Recording → Engine**. All use China-hosted endpoints.

> The name says "providers" (not a single vendor) because the plugin is deliberately multi-provider — adding more China-hosted ASR providers is a natural extension.

> This is a *plugin* for the open-source [TypeWhisper](https://typewhisper.com) app. It does not replace TypeWhisper — it adds cloud transcription engines to it. Push-to-talk UX (key down/up, live preview, insertion, history) is provided entirely by TypeWhisper.

---

## Features

- **Three provider choices, one plugin** — pick Xiaomi, ByteDance, or Volcengine Agent Plan; all implement one-shot `transcribe(audio:)`.
- **Separate billing routes** — MiMo and standard Seed use their respective APIs; Agent Plan uses its dedicated `/plan/` speech endpoint and subscription AFP credits.
- **Mixed Chinese/English out of the box** — language defaults to `auto`.
- **Dictionary Terms on Seed** — TypeWhisper dictionary Terms are forwarded to Seed-ASR as hotwords (`request.corpus.context`, up to 5000 words), improving recognition of names/technical vocabulary. MiMo remains Corrections-only (no documented hotword API).
- **Clean English output** — `enable_auto_lang` is deliberately off so English gets proper ASCII punctuation + capitalization (see [Engine tuning](#engine-tuning)).
- **Secure by default** — API keys live in the macOS Keychain via TypeWhisper's plugin-scoped secrets; nothing is hardcoded or logged.
- **Self-contained bundle** — the SDK is embedded and the bundle is ad-hoc re-signed, so it loads on any Apple Silicon Mac.

---

## Requirements

- macOS 14.0+ (Apple Silicon, `arm64`)
- [TypeWhisper](https://typewhisper.com) 1.5.0+
- Full **Xcode** (the plugin is a `.bundle`; Command Line Tools alone can't build it)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (only for building from source)
- An API key for at least one engine (see [Getting keys](#getting-keys))

---

## Install (build from source)

```bash
git clone https://github.com/yfzhou0904/typewhisper-cn-providers.git
cd typewhisper-cn-providers

# Build + copy into TypeWhisper's Plugins dir
./Scripts/build.sh --install

# ...or build + symlink (handy during development)
./Scripts/build.sh --symlink
```

The bundle is produced at `build/DerivedData/Build/Products/Release/TypeWhisperCNProviders.bundle` and placed in `~/Library/Application Support/TypeWhisper/Plugins/`.

**Restart TypeWhisper** after installing.

## Configure

1. **TypeWhisper → Settings → Integrations** → enable **"CN Providers"**.
2. Enter your API key(s) (stored in the macOS Keychain):
   - **MiMo API key** — from the Xiaomi MiMo console.
   - **Seed ASR API key** — from Volcengine's console (**API Key management**).
   - **Agent Plan API key** — your dedicated key from the Volcengine Agent Plan console, saved in the separate **Volcengine Agent Plan ASR** section.
3. **Settings → Recording → Engine** → choose **Xiaomi MiMo ASR** (`mimo-v2.5-asr`), **ByteDance Seed ASR** (`seed-asr-2.0`), or **Volcengine Agent Plan ASR** (`seed-asr-2.0`).

Agent Plan connects only to `wss://openspeech.bytedance.com/api/v3/plan/sauc/bigmodel_nostream` with `X-Api-Resource-Id: volc.seedasr.sauc.duration`. Its key is stored separately from the standard Seed key. The speech model is fixed; it does not use Agent Plan's Auto model routing or console model switching. The plugin's `.env` is only for the development smoke test; enter the key in the app for normal use.

Per the [official Agent Plan speech guide](https://docs.volcengine.com/docs/ark/agent-plan-personal-voice-model?lang=zh), calls consume subscription AFP credits. Enabling overage billing in the console allows usage to continue with paid overage after credits run out; the plugin does not change that setting. Do not replace the speech endpoint with `https://ark.cn-beijing.volces.com/api/v3`.

> If you were using an earlier build with a different plugin id, TypeWhisper treats this as a new plugin — re-enter your keys once after upgrading.

## Usage

Hold your push-to-talk key, speak, release — TypeWhisper inserts the transcript. Language is auto-detected for mixed Chinese/English. Switch engines any time from **Settings → Recording → Engine**.

---

## How it works

```
Xiaomi:  AudioData → base64 WAV → HTTPS chat-completions (input_audio) → choices[0].message.content
ByteDance: AudioData → gzip binary WS frames → Seed-ASR bigmodel_nostream → result.text
Agent Plan: AudioData → same binary WS protocol → /plan/sauc/bigmodel_nostream → result.text
```

- **Xiaomi MiMo** — one synchronous HTTPS call with the WAV embedded as base64. Simplest path.
- **ByteDance Seed-ASR** — streams the WAV as gzip'd binary frames over a WebSocket and gets the full sentence back at the end (`bigmodel_nostream`). The binary protocol (4-byte header + sequence + size + gzip payload) mirrors ByteDance's official `sauc_websocket_demo.py`.

All three providers implement TypeWhisper's `TranscriptionEnginePlugin.transcribe(audio:)` one-shot contract (no streaming partials). Agent Plan shares the Seed engine's protocol, tuning, and dictionary hotword support, with an independent provider ID, endpoint, and Keychain entry. TTS is outside this transcription plugin's current scope.

## Engine tuning

- **`enable_auto_lang` is OFF** for Seed-ASR. When enabled, auto-language detection can misclassify non-native English as "Chinese English" and emit CJK punctuation (。，) while dropping sentence capitalization (e.g. `let's explore` → `let's。`). With it off, English gets proper ASCII punctuation + caps and Chinese is unaffected. (Assumes no mid-sentence language switching.)
- **`enable_punc` / `enable_itn` / `enable_ddc` are ON** for Seed-ASR, giving punctuation, normalized numbers, and semantic smoothing.
- **Translation is not supported** (`supportsTranslation = false`) — these are pure transcription engines.

## Security

- No API keys in source, git history, the manifest, or logs — Keychain only.
- API keys are stored with TypeWhisper's plugin-scoped Keychain secrets (`storeSecret`/`loadSecret`).

---

## Development

```
Sources/
  TypeWhisperCNProvidersPlugin.swift  # lifecycle, engine registration, primary-engine forwarding
  XiaomiMiMoASREngine.swift           # MiMo HTTPS engine + request/response handling
  ByteDanceSeedASREngine.swift        # Seed-ASR WebSocket engine + protocol
  CNProvidersSettingsView.swift       # combined settings for all three providers
  Support/
    WAV.swift                    # minimal WAV header parsing + chunking
    Gzip.swift                   # gzip encode/decode (raw-deflate → gzip framing)
  manifest.json                  # plugin manifest (id, principal class, etc.)
Scripts/build.sh                 # build + install/symlink
Scripts/smoke-agent-plan.sh       # live ASR check using the production Swift transport
Scripts/smoke-agent-plan.swift    # reads ARK_API_KEY without logging it
project.yml                      # XcodeGen project spec
vendor/TypeWhisperPluginSDK/     # trimmed copy of the TypeWhisper Plugin SDK (see NOTICE)
```

`project.yml` is the source of truth — `Scripts/build.sh` regenerates the Xcode project with `xcodegen` before building, embeds the SDK framework, then ad-hoc re-signs the bundle (macOS refuses to load a bundle whose code seal doesn't cover its nested resources).

### Agent Plan smoke test

Build with `./Scripts/build.sh`. Set `ARK_API_KEY` in your environment or a local `.env` (gitignored), then run against a short 16 kHz mono 16-bit PCM WAV:

```bash
say -v Tingting -o build/agent-plan.aiff '你好，这是火山引擎语音识别测试。'
afconvert -f WAVE -d LEI16@16000 -c 1 build/agent-plan.aiff build/agent-plan.wav
./Scripts/smoke-agent-plan.sh build/agent-plan.wav
# Optional dictionary hotwords:
./Scripts/smoke-agent-plan.sh build/agent-plan.wav 火山引擎
```

This makes a real Agent Plan request and consumes credits. It compiles the plugin's actual transport code and prints the transcript and elapsed time. It never falls back to the standard paid endpoint.

## Getting keys

- **Xiaomi MiMo**: sign up at the Xiaomi MiMo open platform, create a project, and copy an API key.
- **ByteDance Seed-ASR**: from the Volcengine Speech console → **API Key management** — copy the API key and note the resource id (`volc.seedasr.sauc.duration`).
- **Volcengine Agent Plan ASR**: use the dedicated Agent Plan API key, not the standard Speech console key. See the [official speech setup guide](https://docs.volcengine.com/docs/ark/agent-plan-personal-voice-model?lang=zh).

See the in-repo [API reference](docs/API.md) for full endpoint and parameter details.

---

## License

[GPL-3.0](LICENSE). This project links the [TypeWhisperPluginSDK](https://github.com/TypeWhisper/TypeWhisperPluginSDK), which is also GPL-3.0 — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the vendored SDK attribution.
