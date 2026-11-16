/// A platform-independent sRGB color. UI layers convert it to `Color` / `NSColor`.
public struct RGBA: Hashable, Sendable, CustomStringConvertible {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    /// Opacity in `0...1`.
    public let alpha: Double

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: Double = 1) {
        precondition((0...1).contains(alpha), "alpha must be in 0...1")
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `RGBA(hex: 0xFF8A3D)` is `#FF8A3D`.
    public init(hex: UInt32, alpha: Double = 1) {
        precondition(hex <= 0xFFFFFF, "hex must be 0xRRGGBB")
        self.init(
            red: UInt8((hex >> 16) & 0xFF),
            green: UInt8((hex >> 8) & 0xFF),
            blue: UInt8(hex & 0xFF),
            alpha: alpha
        )
    }

    /// Returns the same color with a different opacity.
    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// `#RRGGBB`, uppercase. Opacity is not included.
    public var hexString: String {
        "#" + [red, green, blue].map { byte in
            let digits = String(byte, radix: 16, uppercase: true)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }

    public var description: String {
        alpha == 1 ? hexString : "\(hexString) @ \(alpha)"
    }
}
