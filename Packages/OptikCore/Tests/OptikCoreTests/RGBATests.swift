import Testing
@testable import OptikCore

struct RGBATests {
    @Test func hexRoundTrip() {
        let color = RGBA(hex: 0x0A8B3D)
        #expect(color.red == 0x0A)
        #expect(color.green == 0x8B)
        #expect(color.blue == 0x3D)
        #expect(color.alpha == 1)
        #expect(color.hexString == "#0A8B3D")
    }

    @Test func withAlphaKeepsComponents() {
        let color = RGBA(hex: 0x5EE0C8).withAlpha(0.18)
        #expect(color == RGBA(red: 0x5E, green: 0xE0, blue: 0xC8, alpha: 0.18))
        #expect(color.description == "#5EE0C8 @ 0.18")
    }
}
