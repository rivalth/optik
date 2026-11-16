import AppKit
import OptikCore

/// Watches for ⌘ ⌘ (two quick taps of Command on its own) anywhere in the system.
///
/// Uses a listen-only event tap, which needs the Input Monitoring permission and
/// can't block or change any input. It only looks at the Command key's own code and
/// the modifier flags; for every other key it only notes that "something else was
/// pressed", without reading which key.
@MainActor
final class DoubleCommandMonitor {
    /// Called on the second tap with the event's timestamp (ns since boot).
    var onDoubleTap: ((UInt64) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = DoubleTapDetector()

    /// Left and right Command (`kVK_Command`, `kVK_RightCommand`).
    private static let commandKeyCodes: Set<Int64> = [0x37, 0x36]
    private static let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]

    var isRunning: Bool { tap != nil }

    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt the first time; afterwards the user grants it in
    /// System Settings > Privacy & Security > Input Monitoring.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    /// Returns false when the permission is missing or the tap couldn't be created.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.hasPermission else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                          options: .listenOnly, eventsOfInterest: CGEventMask(mask),
                                          callback: doubleCommandTapCallback, userInfo: refcon) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        detector = DoubleTapDetector()
    }

    /// The few values the monitor reads from an event, copied out on the tap's thread.
    fileprivate struct Sample: Sendable {
        var type: CGEventType
        var timestamp: UInt64
        var keyCode: Int64
        var flags: CGEventFlags
    }

    fileprivate func handle(_ sample: Sample) {
        let type = sample.type
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        case .keyDown:
            _ = detector.handle(.other)
            return
        case .flagsChanged:
            break
        default:
            return
        }
        let time = Double(sample.timestamp) / 1_000_000_000
        let keyCode = sample.keyCode
        let flags = sample.flags
        let input: DoubleTapDetector.Input
        if !Self.commandKeyCodes.contains(keyCode) || !flags.intersection(Self.otherModifiers).isEmpty {
            input = .other
        } else if flags.contains(.maskCommand) {
            input = .down(at: time)
        } else {
            input = .up(at: time)
        }
        if detector.handle(input) {
            onDoubleTap?(sample.timestamp)
        }
    }
}

/// The tap's run loop source sits on the main run loop, so this runs on the main thread.
private func doubleCommandTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                      refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        let monitor = Unmanaged<DoubleCommandMonitor>.fromOpaque(refcon).takeUnretainedValue()
        let isFlags = type == .flagsChanged
        let sample = DoubleCommandMonitor.Sample(
            type: type, timestamp: uptimeNanoseconds(fromEventTimestamp: event.timestamp),
            keyCode: isFlags ? event.getIntegerValueField(.keyboardEventKeycode) : 0,
            flags: isFlags ? event.flags : [])
        MainActor.assumeIsolated { monitor.handle(sample) }
    }
    return Unmanaged.passUnretained(event)
}

/// Event timestamps are documented as nanoseconds since boot, but on Apple silicon
/// they can come in Mach ticks. Use whichever reading lands near "now".
private func uptimeNanoseconds(fromEventTimestamp timestamp: UInt64) -> UInt64 {
    let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    if timestamp > 0, now >= timestamp, now - timestamp < 5_000_000_000 { return timestamp }
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let converted = timestamp * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
    if converted > 0, now >= converted, now - converted < 5_000_000_000 { return converted }
    return now
}
