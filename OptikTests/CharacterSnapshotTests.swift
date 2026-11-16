import AppKit
import OptikCore
import Testing
@testable import Optik

/// Renders every mood's resting pose to PNG for a side-by-side check against
/// `assets/karakter/png`. Off by default; run with
/// `TEST_RUNNER_OPTIK_WRITE_SNAPSHOTS=1 xcodebuild test ...`.
/// Files land in the app container's tmp folder (the test host is sandboxed).
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OPTIK_WRITE_SNAPSHOTS"] == "1"))
struct CharacterSnapshotTests {
    @Test(arguments: Mood.allCases)
    func writeSnapshot(mood: Mood) throws {
        let scale: CGFloat = 2
        let view = OptikCharacterView(frame: CGRect(x: 0, y: 0, width: 180 * scale, height: 200 * scale))
        view.reduceMotion = true
        view.setMood(mood == .waiting ? .happy : .waiting, animated: false)
        view.setMood(mood, animated: false)
        view.layout()

        let width = Int(180 * scale), height = Int(200 * scale)
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor(DesignTokens.Palette.background).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Layers are y-down; the bitmap context is y-up.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        // render(in:) skips the receiver's own transform, so scale the context instead.
        context.scaleBy(x: scale, y: scale)
        view.rootLayerForTesting.render(in: context)

        let image = try #require(context.makeImage())
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "optik-\(mood.rawValue).png")
        let rep = NSBitmapImageRep(cgImage: image)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        print("snapshot: \(url.path)")
    }
}
