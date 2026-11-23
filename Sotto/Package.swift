// swift-tools-version:5.9
import Foundation
import PackageDescription

// Static libraries produced by vendor/whisper.cpp/build (see scripts/setup_whisper.sh)
let vendorBuild = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../vendor/whisper.cpp/build")
    .standardized.path

let package = Package(
    name: "Sotto",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CWhisper"),
        .executableTarget(
            name: "Sotto",
            dependencies: ["CWhisper"],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(vendorBuild)/src",
                    "-L", "\(vendorBuild)/ggml/src",
                    "-L", "\(vendorBuild)/ggml/src/ggml-blas",
                    "-L", "\(vendorBuild)/ggml/src/ggml-metal",
                    "-lwhisper",
                    "-lggml", "-lggml-base", "-lggml-cpu",
                    "-lggml-blas", "-lggml-metal",
                    "-lc++",
                ]),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
    ]
)
