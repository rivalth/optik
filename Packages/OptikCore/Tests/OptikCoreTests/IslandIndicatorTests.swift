import Foundation
import OptikCore
import Testing

struct IslandIndicatorTests {
    @Test func symbolsFollowTheLevel() {
        #expect(IslandIndicator.volumeSymbol(level: 0.5, muted: true) == "speaker.slash.fill")
        #expect(IslandIndicator.volumeSymbol(level: 0, muted: false) == "speaker.slash.fill")
        #expect(IslandIndicator.volumeSymbol(level: 0.2, muted: false) == "speaker.wave.1.fill")
        #expect(IslandIndicator.volumeSymbol(level: 0.9, muted: false) == "speaker.wave.3.fill")
        #expect(IslandIndicator.batterySymbol(level: 0.3, charging: true) == "battery.100percent.bolt")
        #expect(IslandIndicator.batterySymbol(level: 0.05, charging: false) == "battery.0percent")
    }

    @Test func percentAndPreview() {
        #expect(IslandIndicator.percent(0.804) == "%80")
        #expect(IslandIndicator.percent(1.4) == "%100")
        #expect(IslandIndicator(kind: .volume, symbol: "x", level: 1.3).level == 1)
        #expect(IslandIndicator.clipboardPreview("  Yarın 13.00\nikinci satır") == "Yarın 13.00")
        #expect(IslandIndicator.clipboardPreview(String(repeating: "a", count: 80), limit: 10) == "aaaaaaaaaa…")
    }

    @Test func switchesDefaultOnExceptScreenshots() {
        let defaults = UserDefaults(suiteName: "IslandIndicatorTests")!
        defaults.removePersistentDomain(forName: "IslandIndicatorTests")
        #expect(IndicatorKind.volume.isEnabled(in: defaults))
        #expect(!IndicatorKind.capture.isEnabled(in: defaults))
        defaults.set(false, forKey: IndicatorKind.volume.settingsKey)
        #expect(!IndicatorKind.volume.isEnabled(in: defaults))
    }

    @Test func batteryNoticesOnlyWhenWorthIt() {
        var notices = BatteryNotices()
        func reading(_ level: Double, power: Bool, charging: Bool = false) -> BatteryNotices.Reading {
            .init(level: level, isOnPower: power, isCharging: charging)
        }
        #expect(notices.update(reading(0.5, power: false)) == nil)
        #expect(notices.update(reading(0.5, power: true, charging: true)) == .pluggedIn(0.5))
        #expect(notices.update(reading(0.6, power: true, charging: true)) == nil)
        #expect(notices.update(reading(0.6, power: false)) == .unplugged(0.6))
        #expect(notices.update(reading(0.2, power: false)) == .low(0.2))
        #expect(notices.update(reading(0.19, power: false)) == nil)
        #expect(notices.update(reading(0.10, power: false)) == .low(0.10))
        #expect(notices.update(reading(0.09, power: false)) == nil)
        // Straight from 30 % to 9 %: one warning, not two.
        var skipping = BatteryNotices()
        _ = skipping.update(reading(0.3, power: false))
        #expect(skipping.update(reading(0.09, power: false)) == .low(0.09))
        #expect(skipping.update(reading(0.08, power: false)) == nil)
        // Full once while plugged in.
        var full = BatteryNotices()
        _ = full.update(reading(0.98, power: true, charging: true))
        #expect(full.update(reading(1, power: true, charging: false)) == .full)
        #expect(full.update(reading(1, power: true, charging: false)) == nil)
    }
}
