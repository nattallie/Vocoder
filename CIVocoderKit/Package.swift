// swift-tools-version: 5.10
import PackageDescription

// The App/ SwiftUI demo app is NOT a target of this package -- it's built by the
// generated Vocoder.xcodeproj (see project.yml), which depends on the CIVocoderKit
// product below as a local Swift Package. This package only defines the reusable
// DSP library + its tests, both independent of any app/UI target.
//
// Why not a pure-SPM executable target for App, like this package used to have?
// Xcode's "run a Swift Package executable as an iOS app" feature failed to produce
// a real `.app` bundle in testing -- the launched process had an empty Info
// dictionary (no CFBundleIdentifier), crashing BackBoardServices/SpringBoard's
// event routing (BKSHIDEvent) on launch. A real Xcode project with a proper
// Info.plist sidesteps that rough edge entirely.
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
