import AppKit
import OptikCore
import Testing
@testable import Optik

struct ColorTokenTests {
    @Test func nsColorKeepsComponents() throws {
        let color = try #require(NSColor(DesignTokens.Palette.mintTrack).usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 0x5E / 255.0) < 0.001)
        #expect(abs(color.greenComponent - 0xE0 / 255.0) < 0.001)
        #expect(abs(color.blueComponent - 0xC8 / 255.0) < 0.001)
        #expect(abs(color.alphaComponent - 0.18) < 0.001)
    }

    @Test func accentColorAssetMatchesToken() throws {
        let asset = try #require(NSColor(named: "AccentColor")?.usingColorSpace(.sRGB))
        let token = try #require(NSColor(DesignTokens.Palette.accent).usingColorSpace(.sRGB))
        #expect(abs(asset.redComponent - token.redComponent) < 0.001)
        #expect(abs(asset.greenComponent - token.greenComponent) < 0.001)
        #expect(abs(asset.blueComponent - token.blueComponent) < 0.001)
    }
}
