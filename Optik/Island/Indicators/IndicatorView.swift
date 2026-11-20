import OptikCore
import SwiftUI

/// The island's size for a notice: wider than the closed island so the wings have
/// room, one row high, or two with a line of text under the camera.
enum IndicatorLayout {
    static let width: Double = 432
    static let tallHeight: Double = 70

    static func size(for indicator: IslandIndicator) -> DesignTokens.Island.Size {
        let idle = IslandPhase.idle.size
        return indicator.detail == nil
            ? DesignTokens.Island.Size(width: width, height: idle.height, bottomCornerRadius: idle.bottomCornerRadius)
            : DesignTokens.Island.Size(width: width, height: tallHeight, bottomCornerRadius: 22)
    }
}

/// Draws one notice inside the island. Positions are in island points from its
/// top left corner; the coop keeps its closed place at the far left.
struct IndicatorView: View {
    let indicator: IslandIndicator
    let width: CGFloat
    let notchWidth: CGFloat
    let rowHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Each wing: the space beside the camera (half the island without a notch).
    private var wing: CGFloat { max(60, (width - notchWidth) / 2) }

    private var tint: Color {
        Color(indicator.isWarning ? DesignTokens.Palette.warning : DesignTokens.Palette.mint)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: indicator.symbol)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(indicator.kind == .volume || indicator.kind == .brightness ? Color(DesignTokens.Palette.text) : tint)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .frame(width: 26, height: rowHeight)
                .offset(x: 44)

            HStack(spacing: 8) {
                if indicator.kind == .track {
                    PlayingBars(tint: tint, animates: !reduceMotion)
                }
                if let level = indicator.level {
                    LevelBar(level: level, tint: tint)
                }
                if let trailing = indicator.trailing {
                    Text(verbatim: trailing)
                        .font(OptikFont.body(size: 12, weight: .semibold))
                        .foregroundStyle(indicator.isWarning ? tint : Color(DesignTokens.Palette.text))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: wing - 30, height: rowHeight, alignment: .trailing)
            .offset(x: width - wing + 12)

            if let detail = indicator.detail {
                Text(verbatim: detail)
                    .font(OptikFont.body(size: 13, weight: .medium))
                    .foregroundStyle(Color(DesignTokens.Palette.text))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: width - 48)
                    .offset(x: 24, y: rowHeight + 5)
                    .id(detail)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Four mint bars bouncing while a new song starts.
private struct PlayingBars: View {
    let tint: Color
    let animates: Bool
    @State private var up = false

    private static let heights: [CGFloat] = [10, 16, 12, 14]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(Self.heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: height)
                    .scaleEffect(x: 1, y: !animates || up ? 1 : 0.35)
                    .animation(animates ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(index) * 0.11) : nil,
                               value: up)
            }
        }
        .frame(height: 16)
        .onAppear { up = true }
        .accessibilityHidden(true)
    }
}

/// A thin bar with the level in mint, like the system's own.
private struct LevelBar: View {
    let level: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(tint).frame(width: max(5, proxy.size.width * level))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.15), value: level)
        .accessibilityValue(Text(IslandIndicator.percent(level)))
    }
}
