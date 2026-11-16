// swift-tools-version: 6.0
import PackageDescription

// Platform-independent core: models, rules, money and date helpers, tool schemas,
// design tokens. Must not depend on any Apple UI framework (AppKit, UIKit, SwiftUI).
let package = Package(
    name: "OptikCore",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "OptikCore", targets: ["OptikCore"]),
    ],
    targets: [
        .target(name: "OptikCore"),
        .testTarget(name: "OptikCoreTests", dependencies: ["OptikCore"]),
    ]
)
