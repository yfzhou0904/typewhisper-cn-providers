# Setup

## Requirements

- macOS 14.0+ on Apple Silicon.
- [TypeWhisper](https://typewhisper.com) 1.5.0+.
- Full Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build from source.
- An API key for at least one provider.

## Install

```bash
git clone https://github.com/yfzhou0904/typewhisper-cn-providers.git
cd typewhisper-cn-providers
./Scripts/build.sh --install
```

The bundle is installed in `~/Library/Application Support/TypeWhisper/Plugins/`. Restart TypeWhisper after installing.

## Configure

1. Open **Settings → Integrations** and enable **CN Providers**.
2. Enter your key in the matching provider section and save.
3. Open **Settings → Recording → Engine** and choose your provider.

| Provider | API key | Billing |
|---|---|---|
| Xiaomi MiMo ASR | Xiaomi MiMo open platform | Pay as you go |
| ByteDance Seed ASR | Volcengine Speech console → API Key management | Pay as you go |
| Volcengine Agent Plan ASR | Dedicated Agent Plan key from the Volcengine console | Subscription AFP credits |

The two Seed choices use the same Seed-ASR 2.0 model with separate credentials and billing routes. API keys are stored in the macOS Keychain. Development `.env` files are not used by the installed plugin.

Agent Plan consumes subscription credits. If you enable overage billing in the console, usage continues with paid overage after credits run out. See the [official speech setup guide](https://docs.volcengine.com/docs/ark/agent-plan-personal-voice-model?lang=zh) and [API reference](API.md) for details.

## Dictate

Hold your push-to-talk key, speak, and release to insert the transcript. Chinese and English are recognized automatically. Change providers in **Settings → Recording → Engine**.
