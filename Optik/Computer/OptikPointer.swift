import AppKit
import OptikCore
import SwiftUI

/// Optik's own mouse: a mint arrow with a tiny Optik beside it, drawn above every
/// window. It flies to what Optik is about to click and shows the click; the
/// click itself goes through Accessibility, so the user's own pointer stays put.
/// It leaves from the notch the first time and fades out when Optik is done.
@MainActor
final class OptikPointer {
    static let shared = OptikPointer()

    private var panel: NSPanel?
    private let model = PointerModel()
    private var hideTask: Task<Void, Never>?
    /// The pointer fades out this long after its last move.
    static let idleLifetime: Duration = .seconds(3)

    private init() {}

    /// Flies to a point in Accessibility coordinates (top-left origin, global).
    func move(to point: CGPoint) async {
        hideTask?.cancel()
        let screen = Self.screen(containing: point)
        let panel = panel(on: screen)
        let target = Self.local(point, in: screen)
        if !model.isVisible {
            // Out of the notch: the top middle of the screen.
            model.position = CGPoint(x: screen.frame.width / 2, y: 14)
            panel.orderFrontRegardless()
            withAnimation(.easeOut(duration: 0.15)) { model.isVisible = true }
        }
        let distance = hypot(target.x - model.position.x, target.y - model.position.y)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduceMotion ? 0 : min(0.75, 0.25 + distance / 2400)
        withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: duration)) { model.position = target }
        try? await Task.sleep(for: .seconds(duration))
        scheduleHide()
    }

    /// Flies to the point and shows a click there.
    func click(at point: CGPoint) async {
        await move(to: point)
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.08)) { model.isPressed = true }
        model.ripple += 1
        try? await Task.sleep(for: .milliseconds(110))
        withAnimation(.spring(duration: 0.25, bounce: 0.4)) { model.isPressed = false }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleLifetime)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeIn(duration: 0.3)) { self.model.isVisible = false } completion: {
                if !self.model.isVisible { self.panel?.orderOut(nil) }
            }
        }
    }

    private func panel(on screen: NSScreen) -> NSPanel {
        if let panel {
            if panel.frame != screen.frame {
                panel.setFrame(screen.frame, display: false)
                model.isVisible = false
            }
            return panel
        }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: PointerView(model: model))
        panel.setFrame(screen.frame, display: false)
        self.panel = panel
        return panel
    }

    private static func screen(containing point: CGPoint) -> NSScreen {
        let cocoa = CGPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.first { $0.frame.contains(cocoa) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Accessibility coordinates to the panel's own (top-left origin).
    private static func local(_ point: CGPoint, in screen: NSScreen) -> CGPoint {
        let cocoaY = primaryHeight - point.y
        return CGPoint(x: point.x - screen.frame.minX, y: screen.frame.maxY - cocoaY)
    }

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
}

@MainActor @Observable
private final class PointerModel {
    var position = CGPoint.zero
    var isVisible = false
    var isPressed = false
    var ripple = 0
}

private struct PointerView: View {
    let model: PointerModel
    @AppStorage(SettingsKey.accentColor) private var accent = AccentChoice.default

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if model.isVisible {
                ZStack(alignment: .topLeading) {
                    ClickRipple(trigger: model.ripple)
                    PointerArrow()
                        .fill(Color(DesignTokens.Palette.mint))
                        .overlay(PointerArrow().stroke(Color.black.opacity(0.55), lineWidth: 1.2))
                        .frame(width: 17, height: 25)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                        .scaleEffect(model.isPressed ? 0.8 : 1, anchor: .topLeading)
                    OptikView(mood: .thoughtful, scale: 0.12, accent: accent.color,
                              showsGroundShadow: false, isInteractive: false)
                        .frame(width: 24, height: 26)
                        .offset(x: 13, y: 18)
                }
                .offset(x: model.position.x, y: model.position.y)
                .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .topLeading)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The macOS arrow's outline, tip at the top left.
private struct PointerArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let outline: [(x: CGFloat, y: CGFloat)] = [(0, 0), (0, 0.84), (0.2, 0.64), (0.36, 1), (0.48, 0.94), (0.34, 0.6), (0.62, 0.6)]
        let points = outline.map { CGPoint(x: rect.minX + $0.x * rect.height, y: rect.minY + $0.y * rect.height) }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// A mint ring that spreads from the tip on each click.
private struct ClickRipple: View {
    let trigger: Int
    @State private var progress: CGFloat = 1

    var body: some View {
        Circle()
            .stroke(Color(DesignTokens.Palette.mint), lineWidth: 2)
            .frame(width: 34, height: 34)
            .scaleEffect(0.2 + progress * 0.8)
            .opacity(Double(1 - progress))
            .offset(x: -17, y: -17)
            .onChange(of: trigger) {
                progress = 0
                withAnimation(.easeOut(duration: 0.45)) { progress = 1 }
            }
    }
}
