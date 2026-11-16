import OptikCore
import SwiftUI

/// Every mood side by side, plus a large Optik with mood buttons, as in
/// `assets/animasyon/optik-demo.html`. Used to compare the native drawing with the reference.
struct CharacterPreviewView: View {
    @AppStorage(SettingsKey.accentColor) private var accent = AccentChoice.default
    @State private var mood: Mood = .waiting

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Optik")
                    .font(OptikFont.heading(size: 28))
                Text("Bir ruh haline bas: hareketi oynar, sesi çalar. Optik'in üstüne basınca zıplar.")
                    .font(OptikFont.body(size: 15))
                    .foregroundStyle(Color(DesignTokens.Palette.textMuted))
                    .multilineTextAlignment(.center)
            }

            OptikView(mood: mood, scale: 2, accent: accent.color) {
                play(.dinliyor)
            }
            .accessibilityHint(Text("Zıplatmak için bas"))

            MoodButtons(selection: $mood) { play($0.sound) }

            Divider().overlay(Color(DesignTokens.Palette.surfaceSecondary))

            VStack(spacing: 12) {
                Text("Bütün ruh halleri")
                    .font(OptikFont.heading(size: DesignTokens.Typography.sectionTitleSize))
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Mood.allCases, id: \.self) { item in
                        VStack(spacing: 6) {
                            OptikView(mood: item, scale: 0.6, accent: accent.color) { play(.dinliyor) }
                            Text(item.localizedName)
                                .font(OptikFont.body(size: DesignTokens.Typography.secondarySize, weight: .semibold))
                                .foregroundStyle(Color(DesignTokens.Palette.textMuted))
                        }
                    }
                }
            }
        }
        .foregroundStyle(Color(DesignTokens.Palette.text))
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(minWidth: 860)
        .background(Color(DesignTokens.Palette.background))
    }

    private func play(_ effect: SoundEffect) {
        Task { await SoundEffectPlayer.shared.play(effect) }
    }
}

private struct MoodButtons: View {
    @Binding var selection: Mood
    let onSelect: (Mood) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Mood.allCases, id: \.self) { mood in
                Button {
                    selection = mood
                    onSelect(mood)
                } label: {
                    Text(mood.localizedName)
                        .font(OptikFont.body(size: 14, weight: .semibold))
                        .padding(.horizontal, 18)
                        .frame(minHeight: DesignTokens.minimumTapTarget)
                        .background(Color(DesignTokens.Palette.surface), in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                selection == mood ? Color(DesignTokens.Palette.accent) : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mood ? .isSelected : [])
            }
        }
    }
}

#Preview {
    CharacterPreviewView()
}
