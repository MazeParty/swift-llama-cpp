// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let llamaVersion = "b11960"
let llamaChecksum = "feba05e0b7cb5e682ae3354abb455bf9723ae2cc95c69e24d073264e6a34d759"
let llamaRevision = "8642541b255bfb5dc39cd351a178be09013a55d6"

// Upstream releases omit simulator slices. The setup script adds them at the same revision.
let localFramework = "Artifacts/llama-\(llamaVersion).xcframework"
let localFrameworkURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent(localFramework)
let llamaTarget: Target = FileManager.default.fileExists(atPath: localFrameworkURL.path)
    ? .binaryTarget(name: "llama", path: localFramework)
    : .binaryTarget(
        name: "llama",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/\(llamaVersion)/llama-\(llamaVersion)-xcframework.zip",
        checksum: llamaChecksum
    )

let package = Package(
    name: "swift-llama-cpp",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SwiftLlama",
            targets: ["SwiftLlama"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "SwiftLlama",
            dependencies: [
                "llama"
            ]
        ),
        llamaTarget,
        .testTarget(
            name: "SwiftLlamaTests",
            dependencies: ["SwiftLlama"],
            resources: [.copy("Resources")]
        ),
    ]
)
