import OptikCore
import SwiftUI

/// The notch island, laid out like `tasarim-kaynak/03-mac-centik.dc.html`:
/// positions are in island points from its top left corner.
struct IslandView: View {
    let model: IslandModel

    @AppStorage(SettingsKey.accentColor) private var accent = AccentChoice.default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `.isl` transition: 0.45 s, `cubic-bezier(.3,1.25,.5,1)` (overshoots a little).
    static let spring = Animation.timingCurve(0.3, 1.25, 0.5, 1, duration: 0.45)

    private var phase: IslandPhase { model.phase }

    private var shape: UnevenRoundedRectangle {
        let bottom = model.size.bottomCornerRadius
        // Under the notch the top edge is the screen edge; without one it floats as a pill.
        let top = model.hasNotch ? 0 : bottom
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: top)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(DesignTokens.Palette.island)
            coop
            optik
            content
            indicator
            microphoneDot
        }
        .frame(width: model.width, height: model.size.height, alignment: .topLeading)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { model.onClick() }
        .animation(Self.spring, value: phase)
        .animation(Self.spring, value: model.width)
        .animation(Self.spring, value: model.size)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Optik'i çağır"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Coop and Optik

    /// `.coop-idle` translate(16, 5) scale(.44), `.coop-open` translate(24, 80), origin 0 0.
    private var coop: some View {
        CoopDoorView(isOpen: phase.isOpen, reduceMotion: reduceMotion)
            .scaleEffect(phase.isOpen ? 1 : 0.44, anchor: .topLeading)
            .offset(x: phase.isOpen ? 24 : 16, y: phase.isOpen ? 80 : 5)
    }

    /// Optik at half size (90 × 100) without its shadow. The hop out of the coop runs
    /// in Core Animation inside `OptikCharacterView`.
    private var optik: some View {
        OptikView(mood: model.machine.mood, scale: 0.5, accent: accent.color,
                  showsGroundShadow: false, isOutOfCoop: phase.isOpen, isInteractive: false)
            .frame(width: 90, height: 100)
            .offset(x: 84, y: 40)
            .accessibilityHidden(true)
    }

    // MARK: Indicators

    /// A notice in the wings: the symbol beside the coop, a level or a word on the
    /// right of the camera, and a line under it for songs and copied text.
    @ViewBuilder
    private var indicator: some View {
        if phase == .idle, let indicator = model.indicator {
            IndicatorView(indicator: indicator, width: model.width, notchWidth: model.notchWidth,
                          rowHeight: IslandPhase.idle.size.height)
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
        }
    }

    /// Green while the microphone is on (`CLAUDE.md`, privacy).
    @ViewBuilder
    private var microphoneDot: some View {
        if model.isMicrophoneOn && phase.isOpen {
            Circle()
                .fill(Color(DesignTokens.Palette.mint))
                .frame(width: 7, height: 7)
                .offset(x: model.width - 24, y: 16)
                .transition(.opacity)
                .accessibilityLabel(Text("Mikrofon açık"))
        }
    }

    // MARK: Text

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .idle:
                EmptyView()
            case .wake:
                Text(verbatim: model.greeting)
                    .font(OptikFont.heading(size: 40))
                    .padding(.top, 16)
                    .transition(rise)
            case .listening:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ListeningWave(reduceMotion: reduceMotion)
                        Text("Dinliyorum")
                            .font(OptikFont.body(size: 13, weight: .semibold))
                            .foregroundStyle(Color(DesignTokens.Palette.textMuted))
                    }
                    if let transcript = model.machine.transcript, !transcript.isEmpty {
                        // What the user is saying, live (`docs/01-urun.md` 1.1).
                        Text(verbatim: transcript)
                            .font(OptikFont.body(size: 15))
                            .lineLimit(2)
                            .truncationMode(.head)
                            .transition(.opacity)
                    }
                }
                .padding(.top, 10)
                .animation(.easeOut(duration: 0.15), value: model.machine.transcript)
                .transition(rise)
            case .replying:
                reply(model.machine.replyText ?? "")
            case .announcing:
                message(model.machine.currentAnnouncement?.text ?? "")
            }
        }
        .foregroundStyle(Color(DesignTokens.Palette.text))
        .frame(width: max(0, model.width - 196 - 26), alignment: .leading)
        .offset(x: 196, y: 46)
    }

    /// A streamed reply grows in place instead of rising again with every word.
    private func reply(_ text: String) -> some View {
        Text(verbatim: text)
            .font(OptikFont.body(size: 16))
            .lineSpacing(16 * 0.45 - 4)
            .fixedSize(horizontal: false, vertical: true)
            .transition(rise)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(OptikFont.body(size: 16))
            .lineSpacing(16 * 0.45 - 4)
            .fixedSize(horizontal: false, vertical: true)
            .id(text)
            .transition(rise)
    }

    /// `.isl-rise`: fades in from 8 pt below, 0.4 s ease-out after 0.3 s.
    private var rise: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)).animation(.easeOut(duration: 0.4).delay(0.3)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }
}

/// Five mint bars that rise and fall in turn (`.isl-bar`). Runs only while listening.
private struct ListeningWave: View {
    var reduceMotion: Bool
    @State private var up = false

    private static let heights: [CGFloat] = [12, 20, 16, 20, 10]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(DesignTokens.Palette.mint))
                    .frame(width: 4, height: height)
                    .scaleEffect(x: 1, y: reduceMotion || up ? 1 : 0.25)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.12), value: up)
            }
        }
        .frame(height: 20)
        .onAppear { up = true }
        .accessibilityHidden(true)
    }
}
