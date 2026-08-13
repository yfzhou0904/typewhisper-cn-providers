# Third-party notices

## TypeWhisperPluginSDK

This project builds against a **trimmed local copy** of the
[`TypeWhisper/TypeWhisperPluginSDK`](https://github.com/TypeWhisper/TypeWhisperPluginSDK),
vendored under [`vendor/TypeWhisperPluginSDK`](vendor/TypeWhisperPluginSDK).

- **License:** GNU General Public License v3.0 — see [`LICENSE`](LICENSE).
- **Why vendored/trimmed:** the upstream SDK's `Package.swift` pulls in the heavy
  MLX / onnxruntime / mlx-audio dependency graph, which defeats offline/instant
  builds. The core target has no external dependencies (system frameworks only),
  so we vendor just that core and build it self-contained.
- The trimmed copy is derived from the upstream project; all upstream copyright
  and license obligations apply to that directory. Upstream changes should be
  reviewed before vendoring updates.

## ASR services

This plugin is a thin client over two public cloud ASR services. It is **not**
affiliated with or endorsed by their vendors. Use of each service is subject to
the vendor's own terms, and you are responsible for supplying and securing your
own API keys:

- Xiaomi MiMo-V2.5-ASR (Xiaomi)
- ByteDance Seed-ASR 2.0 (Volcengine / ByteDance)
