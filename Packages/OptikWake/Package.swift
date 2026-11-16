// swift-tools-version: 6.0
import PackageDescription

// On-device keyword spotting for the wake word ("Optik"). Core ML and Accelerate
// only, no third-party packages. See NOTICE.md for the adapted code.
let package = Package(
    name: "OptikWake",
    platforms: [.macOS(.v15)],
    products: [.library(name: "OptikWake", targets: ["OptikWake"])],
    targets: [
        .target(name: "OptikWake", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "optik-wake-bench", dependencies: ["OptikWake"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
