# API reference

Endpoints and request shapes for the three provider choices this plugin uses, kept here so
the details are self-contained and don't have to be re-derived.

## Xiaomi MiMo-V2.5-ASR

- **Endpoint:** `POST https://api.xiaomimimo.com/v1/chat/completions`
- **Auth:** `Authorization: Bearer <API_KEY>`
- **Model:** `mimo-v2.5-asr`
- **Request:** OpenAI-compatible chat-completions with an `input_audio` content item:

```json
{
  "model": "mimo-v2.5-asr",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "input_audio", "input_audio": { "data": "data:audio/wav;base64,<B64>" } }
      ]
    }
  ],
  "asr_options": { "language": "auto" }
}
```

- **Transcript:** `choices[0].message.content`
- **`asr_options.language`:** `auto` (default) | `zh` | `en`
- Audio is sent **inline as base64** — no hosting required.

## ByteDance Seed-ASR 2.0

- **Endpoint:** `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream` (non-streaming)
- **Resource id:** `volc.seedasr.sauc.duration` (Seed-ASR 2.0 小时版)
- **Auth headers:** single `X-Api-Key` (modern console method) + `X-Api-Resource-Id` + `X-Api-Request-Id` (UUID).

### Request flags

```json
{
  "user": { "uid": "typewhisper" },
  "audio": { "format": "wav", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1 },
  "request": {
    "model_name": "bigmodel",
    "enable_itn": true,
    "enable_punc": true,
    "enable_ddc": true,
    "enable_auto_lang": false,
    "show_utterances": false,
    "enable_nonstream": false
  }
}
```

- **`enable_auto_lang: false`** — required for clean English (see README). Auto-lang can misclassify non-native English as "Chinese English" and emit CJK punctuation + drop sentence caps.
- **`enable_punc: true`** — gives punctuation (note: even a single word comes back as a forced sentence, `hello` → `Hello.`).
- **`enable_itn`** — normalized numbers/dates. **`enable_ddc`** — semantic smoothing.

### Dictionary terms → Seed hotwords

TypeWhisper dictionary **Terms** are forwarded to Seed as direct hotwords via `request.corpus.context` (a JSON *string* wrapping a `{"hotwords":[...]}` object). This biases decoding toward the configured vocabulary; deterministic **Corrections** are applied host-side by TypeWhisper and are not handled here.

```json
{
  "request": {
    "model_name": "bigmodel",
    "...": "...",
    "corpus": {
      "context": "{\"hotwords\":[{\"word\":\"Qdrant\"},{\"word\":\"psql\"}]}"
    }
  }
}
```

- Only present when the user has dictionary Terms and the host forwards them (`dictionaryTermHints`).
- `bigmodel_nostream` accepts up to **5000 words**; direct hotwords take priority over any server-side hotword table.
- The engine advertises `dictionaryTermsSupport = .supported` with a `DictionaryTermsBudget(maxTerms: 5000)`.

### Wire protocol (binary frames)

The `_nostream` endpoint streams binary frames: `4-byte header` + `4-byte big-endian sequence` + `4-byte big-endian size` + gzip payload.

- Header: `version` (1) / `header size` / `message type` / `flags` / `serialization` (JSON) / `compression` (gzip).
- Message types: `0x1` full client request (JSON), `0x2` audio-only, `0x9` full server response, `0xF` error.
- Sequence numbers are big-endian; a **negative sequence = last audio packet** (triggers finalization).
- Transcript is in `result.text` of the `0x9` response.

### gzip caveat (important)

Apple's `NSData.compressed(using: .zlib)` emits **raw DEFLATE** (no zlib wrapper), so the engine wraps it with a gzip header + trailer on encode and skips the variable-length gzip header + trailer on decode, matching Python's `gzip.compress`/`gzip.decompress` used by ByteDance's official sample. See `Sources/Support/Gzip.swift`.

## Volcengine Agent Plan ASR

- **Provider ID:** `volcengine-agent-plan-asr` (independent of standard Seed).
- **Endpoint:** `wss://openspeech.bytedance.com/api/v3/plan/sauc/bigmodel_nostream`.
- **Resource ID:** `volc.seedasr.sauc.duration`.
- **Auth:** dedicated Agent Plan key in `X-Api-Key`, plus `X-Api-Resource-Id` and a unique `X-Api-Request-Id`.
- **Keychain entry:** `arkAgentPlanApiKey`; standard Seed keeps `bdApiKey`.
- **Model:** Seed-ASR 2.0, with `request.model_name = bigmodel`. No Auto or console-based model switching.
- **Protocol and hotwords:** identical to the standard Seed implementation above.
- **Billing:** subscription AFP credits; paid overage only if enabled in the console and credits are exhausted. The plugin does not enable overage or fall back to another billing route.

The [official Agent Plan speech guide](https://docs.volcengine.com/docs/ark/agent-plan-personal-voice-model?lang=zh) provides the dedicated endpoints and sample protocol. `bigmodel_async` is also available at `wss://openspeech.bytedance.com/api/v3/plan/sauc/bigmodel_async`, but this plugin uses `bigmodel_nostream` to match TypeWhisper's recorded-audio contract and existing hotword support.

Agent Plan also exposes Seed-TTS 2.0 (`X-Api-Resource-Id: seed-tts-2.0`) via `/api/v3/plan/tts/bidirection`, `/api/v3/plan/tts/unidirectional/stream`, and HTTP POST `/api/v3/plan/tts/unidirectional`. TTS is not implemented by this transcription plugin.

## Related flavors (for context)

ByteDance's Seed-ASR ships several flavors; this plugin uses the streaming family only:

| Flavor | Style | Notes |
|---|---|---|
| 单向流式 WebSocket (`bigmodel` / `_nostream` / `_async`) | streaming | What we use (`_nostream`) |
| 录音文件识别 标准版 (`/api/v3/auc/bigmodel/submit` + query) | async submit+poll | whole file, hosted URL |
| 录音文件识别 极速版 `/flash` | synchronous single call | whole file, hosted URL, ≤2h/100MB |

All the non-streaming (file) flavors require the audio to be hosted at a `url`; only the streaming family (and Xiaomi, inline) accept the audio without external hosting — which is why this plugin uses them.
