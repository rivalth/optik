import Foundation

/// The small notices the closed island shows when something on the Mac changes:
/// volume, brightness, charging, a new song… Each can be turned off in Settings.
public enum IndicatorKind: String, CaseIterable, Sendable, Identifiable {
    case volume
    case brightness
    case keyboardLight
    case microphone
    case battery
    case accessory
    case clipboard
    case capture
    case track
    case inputSource

    public var id: String { rawValue }

    /// The user defaults key of its switch.
    public var settingsKey: String { "indicator." + rawValue }

    /// On unless noted: watching the screenshot folder asks for access to it
    /// (usually the Desktop), so that one waits for the user.
    public var isOnByDefault: Bool { self != .capture }

    /// A level moves in small steps while a key is held, so it stays a little;
    /// a notice with text stays long enough to read.
    public var duration: TimeInterval {
        switch self {
        case .volume, .brightness, .keyboardLight: 1.6
        case .microphone, .inputSource, .capture: 2
        case .battery, .accessory, .clipboard: 2.6
        case .track: 3.2
        }
    }

    public func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: settingsKey) as? Bool ?? isOnByDefault
    }
}

/// One notice on the island.
public struct IslandIndicator: Equatable, Sendable {
    public var kind: IndicatorKind
    /// An SF Symbol name.
    public var symbol: String
    /// 0…1 for a bar (volume, brightness).
    public var level: Double?
    /// Short text in the right wing: "%80", "Kopyalandı", "TR".
    public var trailing: String?
    /// A line under the notch: a song, what was copied, a device.
    public var detail: String?
    /// Drawn in the warning color (low battery).
    public var isWarning: Bool

    public init(kind: IndicatorKind, symbol: String, level: Double? = nil, trailing: String? = nil,
                detail: String? = nil, isWarning: Bool = false) {
        self.kind = kind
        self.symbol = symbol
        self.level = level.map { min(1, max(0, $0)) }
        self.trailing = trailing
        self.detail = detail
        self.isWarning = isWarning
    }

    /// "%80", the Turkish way.
    public static func percent(_ fraction: Double) -> String {
        "%\(Int((min(1, max(0, fraction)) * 100).rounded()))"
    }

    /// The speaker for a volume level.
    public static func volumeSymbol(level: Double, muted: Bool) -> String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// The battery for a charge level.
    public static func batterySymbol(level: Double, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// The first line of copied text, short enough for one line under the notch.
    public static func clipboardPreview(_ text: String, limit: Int = 60) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }
}

/// Decides when the battery is worth a notice: plugging in or out, the first time
/// it drops to 20 % and 10 % on battery, and once when it is full.
public struct BatteryNotices: Sendable {
    public struct Reading: Equatable, Sendable {
        public var level: Double
        public var isOnPower: Bool
        public var isCharging: Bool

        public init(level: Double, isOnPower: Bool, isCharging: Bool) {
            self.level = level
            self.isOnPower = isOnPower
            self.isCharging = isCharging
        }
    }

    public enum Notice: Equatable, Sendable {
        case pluggedIn(Double)
        case unplugged(Double)
        case low(Double)
        case full
    }

    private var last: Reading?
    private var warnedAt: Set<Int> = []
    private var toldFull = false

    public static let warningLevels = [20, 10]

    public init() {}

    public mutating func update(_ reading: Reading) -> Notice? {
        defer { last = reading }
        let percent = Int((reading.level * 100).rounded())
        if reading.isOnPower { warnedAt = [] }
        if percent < 95 { toldFull = false }
        // The first reading only sets the scene.
        guard let last else { return nil }
        if reading.isOnPower != last.isOnPower {
            return reading.isOnPower ? .pluggedIn(reading.level) : .unplugged(reading.level)
        }
        if !reading.isOnPower {
            for warning in Self.warningLevels where percent <= warning && !warnedAt.contains(warning) {
                warnedAt.formUnion(Self.warningLevels.filter { $0 >= percent })
                return .low(reading.level)
            }
        }
        if reading.isOnPower, percent >= 100, !toldFull, last.isCharging || Int((last.level * 100).rounded()) < 100 {
            toldFull = true
            return .full
        }
        return nil
    }
}
