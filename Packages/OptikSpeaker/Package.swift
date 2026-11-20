// swift-tools-version: 6.1
import PackageDescription

// Speaker verification for Optik: who is talking, so Optik reacts only to its
// user's voice. A thin wrapper around FluidAudio's CAM++ speaker embedder, with
// every optional FluidAudio subsystem (speech recognition text normalization,
// text to speech, diarization) turned off.
let package = Package(
    name: "OptikSpeaker",
    platforms: [.macOS(.v15)],
    products: [.library(name: "OptikSpeaker", targets: ["OptikSpeaker"])],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.18.3", traits: []),
    ],
    targets: [
        .target(name: "OptikSpeaker", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
    ]
)
