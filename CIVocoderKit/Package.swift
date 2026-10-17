// swift-tools-version: 5.10
import PackageDescription

// CIVocoderKit: the channel-vocoder DSP core, built on Accelerate/vDSP.
// macOS is included alongside iOS purely so `swift test` can run natively
// during development, without needing a simulator for every iteration.
let package = Package(
    name: "Vocoder",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CIVocoderKit", targets: ["CIVocoderKit"])
    ],
    targets: [
        .target(
            name: "CIVocoderKit"
        ),
        .testTarget(
            name: "CIVocoderKitTests",
            dependencies: ["CIVocoderKit"],
            resources: [.copy("Fixtures/reference.json")]
        ),
    ]
)
