// swift-tools-version: 6.0

import PackageDescription

// Minimal local copy of the TypeWhisperPluginSDK containing ONLY the core
// target. The core target has no external dependencies (imports only system
// frameworks), so this resolves and builds without fetching the heavy
// MLX/onnxruntime/mlx-audio package graph that the upstream Package.swift pulls in.
let package = Package(
    name: "TypeWhisperPluginSDK",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TypeWhisperPluginSDK", type: .dynamic, targets: ["TypeWhisperPluginSDK"]),
    ],
    targets: [
        .target(name: "TypeWhisperPluginSDK"),
    ]
)
