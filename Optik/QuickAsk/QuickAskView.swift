import AppKit
import OptikCore
import SwiftUI

/// A Spotlight-like panel under the notch. It takes the keyboard without bringing
/// Optik to the front, drops out of the notch when it opens and goes back into it when
/// it closes, also when the user clicks elsewhere.
final class QuickAskPanel: NSPanel {
    /// The box itself.
    static let width: CGFloat = 600
    /// Room around the box for its shadow and the overshoot of the drop.
    static let margin = NSEdgeInsets(top: 12, left: 40, bottom: 84, right: 40)

    /// The drop from the notch (`cubic-bezier(.2, .9, .25, 1.12)`, 0.62 s).
    static let openAnimation = Animation.timingCurve(0.2, 0.9, 0.25, 1.12, duration: 0.62)
    /// Back into the notch (`cubic-bezier(.16, 1, .3, 1)`, 0.22 s).
    static let closeAnimation = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)

    private let model: QuickAskModel
    /// Bumped on every open, so a close that is still running does not hide the box again.
    private var generation = 0
    private var isClosing = false

    init(model: QuickAskModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width + Self.margin.left + Self.margin.right, height: 160),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        // The view draws its own shadow, which follows the drop.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: QuickAskView(model: model))
        host.sizingOptions = [.preferredContentSize]
        contentView = host
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pinToTop() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    func show() {
        generation += 1
        isClosing = false
        var hidden = Transaction()
        hidden.disablesAnimations = true
        withTransaction(hidden) { model.isShown = false }
        pinToTop()
        makeKeyAndOrderFront(nil)
        // On the next pass, once the hidden state is drawn, so the drop has a start.
        DispatchQueue.main.async { [weak self, model] in
            withAnimation(Self.openAnimation) { model.isShown = true }
            self?.focusField()
        }
    }

    /// The cursor waits in the field: the user types right away, without clicking.
    /// SwiftUI's focus alone is not enough once the box was open before, since its
    /// state still says "focused" while the field lost the first responder.
    private func focusField() {
        model.focusRequest += 1
        if firstResponder is NSText { return }
        if let field = Self.textField(in: contentView) { makeFirstResponder(field) }
    }

    private static func textField(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        if let text = view as? NSTextView, text.isEditable { return text }
        for child in view.subviews { if let found = textField(in: child) { return found } }
        return nil
    }

    func dismiss() {
        guard isVisible, !isClosing else { return }
        isClosing = true
        let closing = generation
        withAnimation(Self.closeAnimation) {
            model.isShown = false
        } completion: { [weak self] in
            guard let self, self.generation == closing else { return }
            self.isClosing = false
            self.orderOut(nil)
        }
    }

    /// Right under the notch (or the menu bar), centered, growing downward.
    private func pinToTop() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let top = screen.frame.maxY - max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let origin = NSPoint(x: screen.frame.midX - frame.width / 2, y: top - frame.height)
        if frame.origin != origin { setFrameOrigin(origin) }
    }
}

/// Silent mode's box, as designed in the "Optik Sessiz Mod" canvas: the chick on the
/// left, the field, a send button; under it the question and the reply, word by word.
struct QuickAskView: View {
    @Bindable var model: QuickAskModel
    @FocusState private var focused: Bool
    @AppStorage(SettingsKey.accentColor) private var accent = AccentChoice.default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let radius: CGFloat = 20
    /// Where the question and the reply start, in line with the field.
    private static let textInset: CGFloat = 70
    private static let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    private static let placeholder = Color(DesignTokens.Palette.textMuted).opacity(0.75)

    var body: some View {
        box
            .frame(width: QuickAskPanel.width)
            .modifier(DropFromNotch(isShown: model.isShown, reduceMotion: reduceMotion))
            .padding(EdgeInsets(top: QuickAskPanel.margin.top, leading: QuickAskPanel.margin.left,
                                bottom: QuickAskPanel.margin.bottom, trailing: QuickAskPanel.margin.right))
            .onChange(of: model.focusRequest, initial: true) {
                // From false, so asking again after the box was closed still moves the cursor.
                focused = false
                DispatchQueue.main.async { focused = true }
            }
            .onExitCommand { model.onClose() }
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow
            if !model.question.isEmpty {
                replyArea
                    .transition(.opacity)
            }
            if model.isOfferingLink {
                linkOffer
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
            footer
        }
        .background {
            // Smoked glass: the desktop blurred behind, darkened almost to black.
            ZStack {
                BlurredBackdrop(cornerRadius: Self.radius)
                Self.shape.fill(Color.black.opacity(0.62))
            }
        }
        .overlay(
            // A faint light along the edge, brighter at the top.
            Self.shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        )
        .overlay {
            if model.isThinking && !reduceMotion {
                ThinkingRing(shape: Self.shape, accent: Color(accent.color))
                    .transition(.opacity.animation(.easeOut(duration: 0.3)))
            }
        }
        .clipShape(Self.shape)
        .shadow(color: .black.opacity(0.55), radius: 30, y: 24)
        .animation(.easeOut(duration: 0.25), value: model.question.isEmpty)
        .animation(.easeOut(duration: 0.3), value: model.isOfferingLink)
    }

    private var inputRow: some View {
        HStack(spacing: 14) {
            chick
            // macOS draws a text field's prompt in its own gray, so the prompt is a
            // label of our own under an empty field.
            TextField(text: $model.text, prompt: nil) { EmptyView() }
            .textFieldStyle(.plain)
            .accessibilityLabel(Text("Optik’e yaz"))
            .background(alignment: .leading) {
                if model.text.isEmpty {
                    Text(prompt)
                        .font(OptikFont.body(size: 18))
                        .foregroundStyle(Self.placeholder)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .font(OptikFont.body(size: 18))
            .foregroundStyle(Color(DesignTokens.Palette.text))
            .tint(Color(accent.color))
            .focused($focused)
            .onSubmit { model.onSubmit() }
            if model.isThinking {
                ThinkingDots(reduceMotion: reduceMotion)
                    .transition(.opacity)
            } else {
                sendButton
                    .transition(.opacity)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(height: 64)
        .animation(.easeOut(duration: 0.2), value: model.isThinking)
    }

    private var prompt: LocalizedStringKey {
        model.question.isEmpty ? "Optik’e yaz… sessizce cevap verir" : "Optik’e yaz…"
    }

    private var chick: some View {
        OptikView(mood: model.mood, scale: 0.25, accent: accent.color, showsGroundShadow: false,
                  isOutOfCoop: true, isInteractive: false)
            .frame(width: 45, height: 50)
            .rotationEffect(.degrees(model.mood == .listening ? -8 : 0), anchor: UnitPoint(x: 0.5, y: 0.9))
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.4), value: model.mood)
            .frame(width: 46, height: 52, alignment: .bottom)
            .accessibilityHidden(true)
    }

    private var sendButton: some View {
        let isEmpty = model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            model.onSubmit()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(DesignTokens.Palette.onAccent))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(accent.color)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isEmpty || model.isWaiting)
        .opacity(isEmpty || model.isWaiting ? 0.35 : 1)
        .animation(.easeOut(duration: 0.15), value: isEmpty)
        .accessibilityLabel(Text("Gönder"))
    }

    private var replyArea: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: model.question)
                        .font(OptikFont.body(size: 13))
                        .foregroundStyle(Color(DesignTokens.Palette.textMuted))
                    reply
                        .font(OptikFont.body(size: 16))
                        .lineSpacing(5)
                        .foregroundStyle(Color(model.isError ? DesignTokens.Palette.warning : DesignTokens.Palette.text))
                        .frame(minHeight: 25, alignment: .topLeading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 16, leading: Self.textInset, bottom: 14, trailing: 22))
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The reply, each word fading up into place after the one before it.
    private var reply: some View {
        let words = QuickAskModel.words(in: model.reply)
        let text = words.enumerated().reduce(Text(verbatim: "")) { text, word in
            text + Text(verbatim: String(word.element)).customAttribute(WordIndex(value: word.offset))
        }
        let starts = reduceMotion ? [] : model.wordStarts
        return TimelineView(.animation(paused: !model.isAnimatingReply || reduceMotion)) { context in
            text.textRenderer(WordFadeRenderer(starts: starts, now: context.date))
        }
    }

    /// "Sayfayı Dia’da açayım mı?" with Yes (⌘⏎) and No. Typing "evet" or "hayır" works too.
    private var linkOffer: some View {
        HStack(spacing: 10) {
            Text(verbatim: DefaultBrowser.offer)
                .font(OptikFont.body(size: 14))
                .foregroundStyle(Color(DesignTokens.Palette.text))
            Spacer(minLength: 8)
            Button {
                model.isOfferingLink = false
            } label: {
                Text("Hayır")
                    .font(OptikFont.body(size: 13, weight: .medium))
                    .foregroundStyle(Color(DesignTokens.Palette.textMuted))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Button {
                model.onOpenLink()
            } label: {
                HStack(spacing: 7) {
                    if let icon = DefaultBrowser.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text("Aç")
                        .font(OptikFont.body(size: 13, weight: .semibold))
                    Text(verbatim: "⌘⏎")
                        .font(OptikFont.body(size: 12))
                        .opacity(0.6)
                }
                .foregroundStyle(Color(DesignTokens.Palette.onAccent))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(Color(accent.color)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel(Text(verbatim: DefaultBrowser.offer))
        }
        .padding(EdgeInsets(top: 2, leading: Self.textInset, bottom: 12, trailing: 16))
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 11, weight: .medium))
                Text("Sessiz · mikrofon kapalı")
            }
            Spacer()
            HStack(spacing: 12) {
                Text("⏎ gönder")
                Text("esc kapat")
            }
        }
        .font(OptikFont.body(size: 12))
        .foregroundStyle(Self.placeholder)
        .padding(EdgeInsets(top: model.question.isEmpty ? 0 : 2, leading: Self.textInset, bottom: 12, trailing: 16))
    }
}

/// What is behind the window, blurred (`NSVisualEffectView` behind the window), with
/// rounded corners. The corners come from a mask image: clipping in SwiftUI does not
/// reach the blur the window server draws.
private struct BlurredBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    /// A stretchable rounded rectangle: only the middle stretches, the corners keep their shape.
    private static func mask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

/// Grows out of the notch's black: from 42 % of the width and 30 % of the height,
/// 34 points higher, blurred.
private struct DropFromNotch: ViewModifier {
    let isShown: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(isShown ? 1 : 0)
        } else {
            content
                .scaleEffect(x: isShown ? 1 : 0.42, y: isShown ? 1 : 0.3, anchor: .top)
                .offset(y: isShown ? 0 : -34)
                .blur(radius: isShown ? 0 : 8)
                .opacity(isShown ? 1 : 0)
        }
    }
}

/// A thin light running around the edge while Optik thinks, from the accent to mint,
/// one turn every 1.6 s.
private struct ThinkingRing: View {
    let shape: RoundedRectangle
    let accent: Color

    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let light = AngularGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.62),
                    .init(color: accent, location: 0.78),
                    .init(color: Color(DesignTokens.Palette.mint), location: 0.86),
                    .init(color: .clear, location: 0.94),
                    .init(color: .clear, location: 1),
                ],
                center: .center,
                angle: .degrees(turn * 360)
            )
            ZStack {
                shape.strokeBorder(light, lineWidth: 5).blur(radius: 6).opacity(0.5)
                shape.strokeBorder(light, lineWidth: 1.2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Three dots blinking one after another while Optik thinks.
private struct ThinkingDots: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color(DesignTokens.Palette.textMuted))
                        .frame(width: 6, height: 6)
                        .opacity(reduceMotion ? 0.6 : Self.opacity(at: time - Double(index) * 0.16))
                }
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityElement()
        .accessibilityLabel(Text("Düşünüyor"))
    }

    /// 25 % most of the time, full at 40 % of each 1.1 s cycle.
    static func opacity(at time: TimeInterval) -> Double {
        let phase = time.truncatingRemainder(dividingBy: 1.1) / 1.1
        let rise = phase < 0.4 ? phase / 0.4 : (phase < 0.8 ? 1 - (phase - 0.4) / 0.4 : 0)
        return 0.25 + 0.75 * rise * rise * (3 - 2 * rise)
    }
}

/// Marks which word of the reply a run of text belongs to.
private struct WordIndex: TextAttribute {
    let value: Int
}

/// Draws each word from 5 points lower and 5 points blurred into place in 0.42 s.
private struct WordFadeRenderer: TextRenderer {
    let starts: [Date]
    let now: Date

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                let progress = progress(of: run[WordIndex.self]?.value)
                if progress >= 1 {
                    context.draw(run)
                } else if progress > 0 {
                    let eased = 1 - pow(1 - progress, 3)
                    var word = context
                    word.opacity = eased
                    word.translateBy(x: 0, y: 5 * (1 - eased))
                    word.addFilter(.blur(radius: 5 * (1 - eased)))
                    word.draw(run)
                }
            }
        }
    }

    private func progress(of index: Int?) -> Double {
        guard let index, starts.indices.contains(index) else { return 1 }
        return min(1, max(0, now.timeIntervalSince(starts[index]) / QuickAskModel.wordDuration))
    }
}
