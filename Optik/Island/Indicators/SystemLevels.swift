import AppKit
import CoreGraphics

/// Display and keyboard brightness. macOS has no public call for either on Apple
/// silicon, so these use the system's own frameworks the way its brightness HUD
/// does, looked up at run time. If a future macOS drops them, the value is nil and
/// the indicator shows without a bar.
enum SystemLevels {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private static let displayServices: GetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    /// The built-in display's brightness, 0…1.
    static func displayBrightness() -> Double? {
        guard let get = displayServices else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        let display = ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
        var value: Float = 0
        guard get(display, &value) == 0 else { return nil }
        return Double(value)
    }

    private typealias KeyboardLevel = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KeyboardIDs = @convention(c) (AnyObject, Selector) -> NSArray?

    @MainActor private static let keyboardClient: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return type.init()
    }()

    /// The keyboard backlight, 0…1.
    @MainActor
    static func keyboardBrightness() -> Double? {
        guard let client = keyboardClient else { return nil }
        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        let levelSelector = NSSelectorFromString("brightnessForKeyboard:")
        guard client.responds(to: idsSelector), client.responds(to: levelSelector) else { return nil }
        let ids = unsafeBitCast(client.method(for: idsSelector), to: KeyboardIDs.self)(client, idsSelector)
        guard let id = (ids?.firstObject as? NSNumber)?.uint64Value else { return nil }
        let level = unsafeBitCast(client.method(for: levelSelector), to: KeyboardLevel.self)(client, levelSelector, id)
        return Double(level)
    }
}
