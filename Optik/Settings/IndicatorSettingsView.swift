import OptikCore
import SwiftUI

/// Settings → Göstergeler: one card per notice the island can show, each with its
/// own switch, like the system's own HUDs but in the notch.
struct IndicatorSettingsView: View {
    @State private var enabled: [IndicatorKind: Bool] = Dictionary(
        uniqueKeysWithValues: IndicatorKind.allCases.map { ($0, $0.isEnabled(in: .standard)) }
    )

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Mac'te bir şey değişince adacık bir anlığına gösterir. Kapattığın gösterge hiç dinlenmez.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(IndicatorKind.allCases) { kind in
                        IndicatorCard(kind: kind, isOn: enabled[kind] ?? false) {
                            toggle(kind)
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(height: 470)
    }

    private func toggle(_ kind: IndicatorKind) {
        let on = !(enabled[kind] ?? false)
        enabled[kind] = on
        UserDefaults.standard.set(on, forKey: kind.settingsKey)
        IslandController.shared.indicators.refresh()
        // A sample on the island, so the user sees what it looks like.
        if on { IslandController.shared.show(kind.sample) }
    }
}

private struct IndicatorCard: View {
    let kind: IndicatorKind
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: kind.settingsSymbol)
                    .font(.system(size: 24, weight: .regular))
                    .frame(height: 30)
                    .foregroundStyle(isOn ? .primary : .secondary)
                Text(kind.localizedName)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                if let note = kind.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(isOn ? 0.08 : 0.04)))
            .overlay(alignment: .topTrailing) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isOn ? Color(DesignTokens.Palette.mint) : .secondary)
                    .padding(10)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(kind.localizedName))
        .accessibilityValue(Text(isOn ? "Açık" : "Kapalı"))
        .accessibilityAddTraits(.isToggle)
    }
}

extension IndicatorKind {
    var localizedName: String {
        switch self {
        case .volume: String(localized: "Ses düzeyi")
        case .brightness: String(localized: "Parlaklık")
        case .keyboardLight: String(localized: "Klavye ışığı")
        case .microphone: String(localized: "Mikrofon")
        case .battery: String(localized: "Pil")
        case .accessory: String(localized: "Kulaklık ve hoparlör")
        case .clipboard: String(localized: "Pano")
        case .capture: String(localized: "Ekran görüntüleri")
        case .track: String(localized: "Yeni şarkı")
        case .inputSource: String(localized: "Klavye dili")
        }
    }

    var note: String? {
        switch self {
        case .brightness, .keyboardLight: String(localized: "Tuşla değiştirince")
        case .microphone: String(localized: "Sessize alınınca ya da açılınca")
        case .accessory: String(localized: "AirPods gibi kablosuz cihazlar")
        case .clipboard: String(localized: "Şifreler gösterilmez")
        case .capture: String(localized: "Ekran görüntüsü klasörüne erişim ister")
        case .track: String(localized: "Spotify ve Müzik")
        default: nil
        }
    }

    var settingsSymbol: String {
        switch self {
        case .volume: "speaker.wave.2"
        case .brightness: "sun.max"
        case .keyboardLight: "light.max"
        case .microphone: "mic"
        case .battery: "battery.75percent"
        case .accessory: "headphones"
        case .clipboard: "doc.on.clipboard"
        case .capture: "camera.viewfinder"
        case .track: "music.note"
        case .inputSource: "keyboard"
        }
    }

    /// What the island shows when the switch is turned on.
    var sample: IslandIndicator {
        switch self {
        case .volume: IslandIndicator(kind: self, symbol: "speaker.wave.2.fill", level: 0.6)
        case .brightness: IslandIndicator(kind: self, symbol: "sun.max.fill", level: 0.75)
        case .keyboardLight: IslandIndicator(kind: self, symbol: "light.max", level: 0.5)
        case .microphone: IslandIndicator(kind: self, symbol: "mic.fill", trailing: String(localized: "Açık"))
        case .battery: IslandIndicator(kind: self, symbol: "battery.100percent.bolt", level: 0.8, trailing: "%80")
        case .accessory: IslandIndicator(kind: self, symbol: "airpodspro", detail: String(localized: "Ada'nın AirPods Pro'su bağlandı"))
        case .clipboard: IslandIndicator(kind: self, symbol: "doc.on.clipboard.fill", trailing: String(localized: "Kopyalandı"),
                                         detail: String(localized: "Yarın 13.00'te Leyla Hoca ile görüşme"))
        case .capture: IslandIndicator(kind: self, symbol: "camera.viewfinder", trailing: String(localized: "Kaydedildi"))
        case .track: IslandIndicator(kind: self, symbol: "music.note", detail: "Kuzu Kuzu · Tarkan")
        case .inputSource: IslandIndicator(kind: self, symbol: "keyboard", trailing: "TR", detail: String(localized: "Türkçe Q"))
        }
    }
}
