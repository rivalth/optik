import AppKit
import OptikCore
import QuartzCore

/// Optik drawn with Core Animation layers. Loops run in the render server, so the app
/// process stays idle while Optik moves. Layer names follow `optik.css`.
final class OptikCharacterView: NSView {
    // MARK: Public state

    private(set) var mood: Mood = .waiting
    var onTap: (() -> Void)?

    var scale: CGFloat = 1 {
        didSet { guard scale != oldValue else { return }; layoutCharacter(); invalidateIntrinsicContentSize() }
    }

    var accentColor: RGBA = DesignTokens.Palette.accent {
        didSet { guard accentColor != oldValue else { return }; applyColors() }
    }

    var reduceMotion = false {
        didSet { guard reduceMotion != oldValue else { return }; apply(mood: mood, animated: false) }
    }

    // MARK: Layers

    private let stage = CALayer()      // design box, scaled
    private let groundShadow = CAShapeLayer() // golge
    private let tapLayer = CALayer()    // dokun
    private let body = CALayer()        // hareket
    private let backSway = CALayer()    // salin (inner wall)
    private let innerWall = CAShapeLayer()
    private let leftLeg = CAShapeLayer()
    private let rightLeg = CAShapeLayer()
    private let frontSway = CALayer()   // salin (shell)
    private let shell = CALayer()
    private let shellFill = CAShapeLayer()
    private let shellShade = CAShapeLayer()
    private let shellMask = CAShapeLayer()
    private let specks = (0..<3).map { _ in CAShapeLayer() }
    private let crack = CAShapeLayer()
    private let hole = CALayer()
    private let holeFill = CAShapeLayer()
    private let holeMask = CAShapeLayer()
    private let leftEyeWrap = CALayer()  // goz-sar
    private let rightEyeWrap = CALayer()
    private let leftEye = CAShapeLayer() // goz
    private let rightEye = CAShapeLayer()
    private let beak = CAShapeLayer()    // gaga
    private let sparkles = CharacterGeometry.sparkles.map { _ in CAShapeLayer() } // pul
    private let sleepLetters = (0..<3).map { _ in CATextLayer() }                 // zz
    private let alertMark = CATextLayer()                                         // unlem

    /// Eye wrappers are this big; the eye path is centered inside.
    private static let eyeWrapSize = CGSize(width: 24, height: 24)

    private static let loopKey = "optik.loop"
    private static let transitionKey = "optik.transition"
    private static let bounceKey = "optik.bounce"

    private var isPaused = false

    // MARK: Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        buildLayers()
        apply(mood: .waiting, animated: false)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CharacterGeometry.designSize.width * scale, height: CharacterGeometry.designSize.height * scale)
    }

    override func layout() {
        super.layout()
        layoutCharacter()
    }

    override func mouseDown(with event: NSEvent) {
        bounce()
        onTap?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Window visibility

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeBackingPropertiesNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(backingChanged),
                                               name: NSWindow.didChangeBackingPropertiesNotification, object: window)
        updateTextScale()
        windowVisibilityChanged()
    }

    /// Hidden or fully covered: freeze every animation so the render server does no work.
    @objc private func windowVisibilityChanged() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        setPaused(!visible)
    }

    @objc private func backingChanged() {
        updateTextScale()
    }

    private func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            let time = stage.convertTime(CACurrentMediaTime(), from: nil)
            stage.speed = 0
            stage.timeOffset = time
        } else {
            let pausedTime = stage.timeOffset
            stage.speed = 1
            stage.timeOffset = 0
            stage.beginTime = 0
            stage.beginTime = stage.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        }
    }

    // MARK: Building

    private func buildLayers() {
        guard let root = layer else { return }
        withoutActions {
            root.masksToBounds = false
            stage.anchorPoint = .zero
            stage.bounds = CGRect(origin: .zero, size: CharacterGeometry.designSize)
            root.addSublayer(stage)

            // golge
            groundShadow.frame = CharacterGeometry.shadowFrame
            groundShadow.path = CGPath(ellipseIn: CGRect(origin: .zero, size: CharacterGeometry.shadowFrame.size), transform: nil)
            groundShadow.fillColor = NSColor.black.cgColor
            groundShadow.opacity = CharacterGeometry.shadowOpacity
            stage.addSublayer(groundShadow)

            // dokun > hareket
            setFrame(tapLayer, CharacterGeometry.bodyFrame, anchor: CGPoint(x: 0.5, y: 1))
            stage.addSublayer(tapLayer)
            setFrame(body, CharacterGeometry.bodyFrame, anchor: CGPoint(x: 0.5, y: 1))
            tapLayer.addSublayer(body)

            // Extras first: in the CSS they sit behind the shell.
            for (layer, sparkle) in zip(sparkles, CharacterGeometry.sparkles) {
                layer.frame = sparkle.frame
                layer.path = CGPath(rect: CGRect(origin: .zero, size: sparkle.frame.size), transform: nil)
                layer.opacity = 0
                body.addSublayer(layer)
            }
            for letter in sleepLetters {
                configureText(letter, "z", size: CharacterGeometry.sleepLetterFontSize,
                              origin: CharacterGeometry.sleepLetterOrigin)
                letter.opacity = 0
                body.addSublayer(letter)
            }
            configureText(alertMark, "!", size: CharacterGeometry.alertMarkFontSize,
                          origin: CharacterGeometry.alertMarkOrigin, lineHeight: CharacterGeometry.alertMarkFontSize)
            alertMark.opacity = 0
            body.addSublayer(alertMark)

            // salin (back) > ic-duvar
            setFrame(backSway, CharacterGeometry.swayFrame, anchor: CGPoint(x: 0.5, y: 1))
            body.addSublayer(backSway)
            innerWall.frame = CharacterGeometry.innerWallFrame
            innerWall.path = CGPath(ellipseIn: CGRect(origin: .zero, size: CharacterGeometry.innerWallFrame.size), transform: nil)
            innerWall.fillColor = NSColor(DesignTokens.CharacterPalette.innerWall).cgColor
            backSway.addSublayer(innerWall)

            // bacaklar
            for (leg, origin) in [(leftLeg, CharacterGeometry.leftLegOrigin), (rightLeg, CharacterGeometry.rightLegOrigin)] {
                setFrame(leg, CGRect(origin: origin, size: CharacterGeometry.legSize), anchor: CGPoint(x: 0.5, y: 0))
                leg.path = CharacterGeometry.legPath
                leg.fillColor = nil
                leg.lineWidth = CharacterGeometry.legLineWidth
                leg.lineCap = .round
                leg.lineJoin = .round
                body.addSublayer(leg)
            }

            // salin (front) > kabuk
            setFrame(frontSway, CharacterGeometry.swayFrame, anchor: CGPoint(x: 0.5, y: 1))
            body.addSublayer(frontSway)
            shell.frame = CharacterGeometry.shellFrame
            shellMask.path = CharacterGeometry.shellPath
            shell.mask = shellMask
            frontSway.addSublayer(shell)

            shellFill.path = CharacterGeometry.shellPath
            shellFill.fillColor = NSColor(DesignTokens.CharacterPalette.shell).cgColor
            shell.addSublayer(shellFill)
            shellShade.path = CharacterGeometry.shellShadePath
            shellShade.fillColor = NSColor(DesignTokens.CharacterPalette.shellShade).cgColor
            shell.addSublayer(shellShade)

            for (speck, frame) in zip(specks, CharacterGeometry.speckFrames) {
                speck.frame = frame
                speck.path = CGPath(ellipseIn: CGRect(origin: .zero, size: frame.size), transform: nil)
                speck.fillColor = NSColor(DesignTokens.CharacterPalette.speck).cgColor
                shell.addSublayer(speck)
            }
            crack.path = CharacterGeometry.crackPath
            crack.fillColor = nil
            crack.strokeColor = NSColor(DesignTokens.CharacterPalette.crack).cgColor
            crack.lineWidth = CharacterGeometry.crackLineWidth
            crack.lineCap = .round
            crack.lineJoin = .round
            shell.addSublayer(crack)

            // delik > gözler, gaga
            hole.frame = CharacterGeometry.holeFrame
            holeMask.path = CharacterGeometry.holePath
            hole.mask = holeMask
            shell.addSublayer(hole)
            holeFill.path = CharacterGeometry.holePath
            holeFill.fillColor = NSColor(DesignTokens.CharacterPalette.hole).cgColor
            hole.addSublayer(holeFill)

            for (wrap, eye) in [(leftEyeWrap, leftEye), (rightEyeWrap, rightEye)] {
                wrap.bounds = CGRect(origin: .zero, size: Self.eyeWrapSize)
                eye.frame = wrap.bounds
                eye.fillColor = NSColor(DesignTokens.CharacterPalette.eye).cgColor
                wrap.addSublayer(eye)
                hole.addSublayer(wrap)
            }

            setFrame(beak, CharacterGeometry.beakFrame, anchor: CGPoint(x: 0.5, y: 0))
            beak.path = CharacterGeometry.beakPath
            hole.addSublayer(beak)

            applyColors()
        }
    }

    private func configureText(_ layer: CATextLayer, _ text: String, size: CGFloat, origin: CGPoint,
                               lineHeight: CGFloat? = nil) {
        let font = Self.headingFont(size: size)
        layer.string = text
        layer.font = font
        layer.fontSize = size
        layer.alignmentMode = .left
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
        let height = lineHeight ?? ceil(font.ascender - font.descender + font.leading)
        layer.frame = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    }

    private static func headingFont(size: CGFloat) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: DesignTokens.Typography.headingFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.bold],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    private func applyColors() {
        let accent = NSColor(accentColor).cgColor
        let mint = NSColor(DesignTokens.Palette.mint).cgColor
        withoutActions {
            leftLeg.strokeColor = accent
            rightLeg.strokeColor = accent
            beak.fillColor = accent
            alertMark.foregroundColor = NSColor(DesignTokens.Palette.warning).cgColor
            for letter in sleepLetters { letter.foregroundColor = mint }
            for (layer, sparkle) in zip(sparkles, CharacterGeometry.sparkles) {
                layer.fillColor = sparkle.usesAccent ? accent : mint
            }
        }
    }

    private func layoutCharacter() {
        withoutActions {
            stage.position = .zero
            stage.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
        updateTextScale()
    }

    private func updateTextScale() {
        let contentsScale = (window?.backingScaleFactor ?? 2) * scale
        withoutActions {
            for text in sleepLetters + [alertMark] { text.contentsScale = contentsScale }
        }
    }

    // MARK: Moods

    func setMood(_ newMood: Mood, animated: Bool) {
        guard newMood != mood else { return }
        apply(mood: newMood, animated: animated)
    }

    /// The tap reaction (`optik-zipla`). Also plays on every mood change.
    func bounce() {
        guard !reduceMotion else { return }
        tapLayer.removeAnimation(forKey: Self.bounceKey)
        tapLayer.add(CharacterAnimations.bounce(), forKey: Self.bounceKey)
    }

    private var loopLayers: [CALayer] {
        [groundShadow, body, backSway, frontSway, leftLeg, rightLeg, leftEyeWrap, rightEyeWrap, beak, alertMark]
            + sparkles + sleepLetters
    }

    private func apply(mood newMood: Mood, animated: Bool) {
        mood = newMood
        setAccessibilityLabel(Self.accessibilityLabel(for: newMood))
        let transition = animated && !reduceMotion

        withoutActions {
            for layer in loopLayers { layer.removeAnimation(forKey: Self.loopKey) }
            for (index, layer) in (sleepLetters as [CALayer]).enumerated() { layer.removeAnimation(forKey: "\(Self.loopKey).\(index)") }
            for (index, layer) in (sparkles as [CALayer]).enumerated() { layer.removeAnimation(forKey: "\(Self.loopKey).\(index)") }

            applyFace(for: newMood, transition: transition)
            applyStaticPose(for: newMood, transition: transition)
        }

        if !reduceMotion {
            addLoops(for: newMood)
        }
    }

    /// Eyes and beak: the only things that still change when motion is reduced.
    private func applyFace(for mood: Mood, transition: Bool) {
        let eyes = EyeShape.eyes(for: mood)
        let centers = CharacterGeometry.eyeCenterX(width: eyes.left.width)
        let wrapCenter = CGPoint(x: Self.eyeWrapSize.width / 2, y: Self.eyeWrapSize.height / 2)

        for (wrap, eye, shape, x) in [(leftEyeWrap, leftEye, eyes.left, centers.left),
                                      (rightEyeWrap, rightEye, eyes.right, centers.right)] {
            let position = CGPoint(x: x, y: CharacterGeometry.eyeRowCenterY)
            let path = shape.path(centeredAt: wrapCenter)
            if transition {
                animateShapeChange(wrap, keyPath: "position", to: NSValue(point: position))
                animateShapeChange(eye, keyPath: "path", to: path)
            }
            wrap.position = position
            eye.path = path
        }

        let beakScale: CGFloat = switch mood {
        case .alert: 1.6
        case .celebrating: 1.5
        default: 1
        }
        let beakTransform = CATransform3DMakeScale(1, beakScale, 1)
        if transition { animateShapeChange(beak, keyPath: "transform", to: NSValue(caTransform3D: beakTransform)) }
        beak.transform = beakTransform
    }

    /// Non-looping pose that belongs to a mood (uykulu legs), plus the rest pose
    /// that replaces a loop when motion is reduced.
    private func applyStaticPose(for mood: Mood, transition: Bool) {
        let legTransform = mood == .sleepy ? CATransform3DMakeScale(1, 0.3, 1) : CATransform3DIdentity
        for leg in [leftLeg, rightLeg] {
            if transition {
                animateShapeChange(leg, keyPath: "transform", to: NSValue(caTransform3D: legTransform), duration: 0.3)
            }
            leg.transform = legTransform
        }

        let swayRest: CATransform3D = switch mood {
        case .sleepy where reduceMotion: CharacterAnimations.sleepRest
        case .listening where reduceMotion: CharacterAnimations.leanRest
        default: CATransform3DIdentity
        }
        backSway.transform = swayRest
        frontSway.transform = swayRest
        body.transform = CATransform3DIdentity
        groundShadow.transform = CATransform3DIdentity
        groundShadow.opacity = CharacterGeometry.shadowOpacity
        for wrap in [leftEyeWrap, rightEyeWrap] { wrap.transform = CATransform3DIdentity }

        alertMark.opacity = mood == .alert ? 1 : 0
        for sparkle in sparkles { sparkle.opacity = 0 }
        for letter in sleepLetters { letter.opacity = 0 }
    }

    private func addLoops(for mood: Mood) {
        typealias A = CharacterAnimations
        let now = stage.convertTime(CACurrentMediaTime(), from: nil)

        func loop(_ layer: CALayer, _ animation: CAAnimation, delay: CFTimeInterval = 0, key: String = OptikCharacterView.loopKey) {
            animation.isRemovedOnCompletion = false
            if delay > 0 { animation.beginTime = now + delay }
            layer.add(animation, forKey: key)
        }

        // Defaults that every mood keeps unless it overrides them.
        var sway: CAAnimation? = A.idleSway()
        var shadowLoop: CAAnimation = A.shadowBreath()
        var eyeLoop: CAAnimation? = A.blink()

        switch mood {
        case .waiting:
            break
        case .happy:
            sway = A.happySway()
            loop(leftLeg, A.step(duration: 1))
            loop(rightLeg, A.step(duration: 1), delay: 0.5)
        case .listening:
            sway = A.lean()
            loop(beak, A.talk())
        case .thoughtful:
            sway = A.tilt()
            loop(rightLeg, A.tapFoot())
        case .alert:
            loop(body, A.shiver())
            loop(leftLeg, A.step(duration: 0.36))
            loop(rightLeg, A.step(duration: 0.36), delay: 0.18)
            loop(alertMark, A.blinkMark())
        case .celebrating:
            eyeLoop = A.sparkleEyes()
            loop(body, A.hop())
            shadowLoop = A.hopShadow()
            loop(leftLeg, A.kick(degrees: 30))
            loop(rightLeg, A.kick(degrees: -30))
            for (index, layer) in sparkles.enumerated() {
                loop(layer, A.sparkle(), delay: 0.2 * Double(index), key: "\(Self.loopKey).\(index)")
            }
        case .sleepy:
            eyeLoop = nil
            sway = A.sleepBreath()
            for (index, layer) in sleepLetters.enumerated() {
                loop(layer, A.sleepLetter(), delay: 0.9 * Double(index), key: "\(Self.loopKey).\(index)")
            }
        }

        if let sway {
            loop(backSway, sway)
            loop(frontSway, sway.copy() as! CAAnimation)
        }
        loop(groundShadow, shadowLoop)
        if let eyeLoop {
            loop(leftEyeWrap, eyeLoop)
            loop(rightEyeWrap, eyeLoop.copy() as! CAAnimation)
        }
    }

    /// Eye, beak and leg changes: 0.28s with overshoot, like the CSS transitions.
    private func animateShapeChange(_ layer: CALayer, keyPath: String, to value: Any,
                                    duration: CFTimeInterval = Double(DesignTokens.Motion.shapeTransitionMilliseconds) / 1000) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = (layer.presentation() ?? layer).value(forKeyPath: keyPath)
        animation.toValue = value
        animation.duration = duration
        let curve = DesignTokens.Motion.overshootCurve
        animation.timingFunction = CAMediaTimingFunction(
            controlPoints: Float(curve.x1), Float(curve.y1), Float(curve.x2), Float(curve.y2))
        layer.add(animation, forKey: "\(Self.transitionKey).\(keyPath)")
    }

    // MARK: Helpers

    private func setFrame(_ layer: CALayer, _ frame: CGRect, anchor: CGPoint) {
        layer.anchorPoint = anchor
        layer.frame = frame
    }

    private func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    private static func accessibilityLabel(for mood: Mood) -> String {
        String(localized: "Optik, \(mood.localizedName)")
    }

    // MARK: Test hooks

    #if DEBUG

    var loopAnimationCount: Int {
        loopLayers.reduce(0) { count, layer in
            count + (layer.animationKeys()?.filter { $0.hasPrefix(Self.loopKey) }.count ?? 0)
        }
    }

    var swayTransformForTesting: CATransform3D { frontSway.transform }
    var leftEyePositionForTesting: CGPoint { leftEyeWrap.position }
    var rootLayerForTesting: CALayer { stage }
    #endif
}
