import QuartzCore

/// The `@keyframes optik-*` rules of `assets/animasyon/optik.css`, as Core Animation.
/// Every function returns a fresh, infinitely repeating animation unless noted.
enum CharacterAnimations {
    typealias T = CSSTransform

    // MARK: Building blocks

    /// A keyframe animation of `keyPath` where CSS applies `timing` to every segment.
    static func keyframes(
        _ keyPath: String,
        duration: CFTimeInterval,
        keyTimes: [Double],
        values: [Any],
        timing: CAMediaTimingFunction,
        repeats: Bool = true
    ) -> CAKeyframeAnimation {
        precondition(keyTimes.count == values.count)
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.duration = duration
        animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
        animation.values = values
        animation.timingFunctions = Array(repeating: timing, count: max(values.count - 1, 1))
        animation.calculationMode = .linear
        animation.repeatCount = repeats ? .infinity : 0
        animation.isRemovedOnCompletion = !repeats
        return animation
    }

    static func transforms(
        duration: CFTimeInterval, keyTimes: [Double], _ values: [CATransform3D], timing: CAMediaTimingFunction
    ) -> CAKeyframeAnimation {
        keyframes("transform", duration: duration, keyTimes: keyTimes,
                  values: values.map { NSValue(caTransform3D: $0) }, timing: timing)
    }

    /// CSS `animation-direction: alternate`: one leg lasts `duration`.
    static func alternating(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval,
                            timing: CAMediaTimingFunction) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = timing
        animation.isRemovedOnCompletion = false
        return animation
    }

    static func group(_ animations: [CAAnimation], duration: CFTimeInterval) -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        return group
    }

    // MARK: Keyframes

    /// optik-salin: 2.8s ease-in-out. The default sway.
    static func idleSway() -> CAAnimation {
        let rest = T.make(.translate(0, 0), .rotate(degrees: -1.5))
        let mid = T.make(.translate(0, -3), .rotate(degrees: 1.5))
        return transforms(duration: 2.8, keyTimes: [0, 0.5, 1], [rest, mid, rest], timing: CSSTiming.easeInOut)
    }

    /// optik-golge: 2.8s ease-in-out.
    static func shadowBreath() -> CAAnimation {
        let a = T.make(.scale(1, 1)), b = T.make(.scale(0.94, 0.94))
        return transforms(duration: 2.8, keyTimes: [0, 0.5, 1], [a, b, a], timing: CSSTiming.easeInOut)
    }

    /// optik-kirp: 4.2s ease. Blink.
    static func blink() -> CAAnimation {
        keyframes("transform.scale.y", duration: 4.2, keyTimes: [0, 0.93, 0.96, 1],
                  values: [1, 1, 0.1, 1], timing: CSSTiming.ease)
    }

    /// optik-sallan: 1s ease-in-out (mutlu).
    static func happySway() -> CAAnimation {
        let a = T.make(.rotate(degrees: -5)), b = T.make(.rotate(degrees: 5))
        return transforms(duration: 1, keyTimes: [0, 0.5, 1], [a, b, a], timing: CSSTiming.easeInOut)
    }

    /// optik-adim: a step. `duration` is 1s (mutlu) or 0.36s (uyari).
    static func step(duration: CFTimeInterval) -> CAAnimation {
        let down = T.make(.translate(0, 0)), up = T.make(.translate(0, -7))
        return transforms(duration: duration, keyTimes: [0, 0.25, 0.5, 1], [down, up, down, down],
                          timing: CSSTiming.easeInOut)
    }

    /// optik-egil: 1.8s ease-in-out (dinliyor).
    static func lean() -> CAAnimation {
        let a = T.make(.rotate(degrees: -8)), b = T.make(.rotate(degrees: -5), .translate(0, -2))
        return transforms(duration: 1.8, keyTimes: [0, 0.5, 1], [a, b, a], timing: CSSTiming.easeInOut)
    }

    /// optik-konus: 0.3s ease-in-out alternate (dinliyor beak).
    static func talk() -> CAAnimation {
        alternating("transform.scale.y", from: 0.6, to: 1.8, duration: 0.3, timing: CSSTiming.easeInOut)
    }

    /// optik-yat: 2.6s ease-in-out (dusunceli).
    static func tilt() -> CAAnimation {
        let a = T.make(.rotate(degrees: -6)), b = T.make(.rotate(degrees: 4))
        return transforms(duration: 2.6, keyTimes: [0, 0.5, 1], [a, b, a], timing: CSSTiming.easeInOut)
    }

    /// optik-tempo: 0.6s ease-in-out (dusunceli right foot).
    static func tapFoot() -> CAAnimation {
        let a = T.make(.rotate(degrees: 0)), b = T.make(.rotate(degrees: -14))
        return transforms(duration: 0.6, keyTimes: [0, 0.5, 1], [a, b, a], timing: CSSTiming.easeInOut)
    }

    /// optik-titre: 1.4s ease-in-out (uyari).
    static func shiver() -> CAAnimation {
        func f(_ x: CGFloat, _ r: CGFloat) -> CATransform3D { T.make(.translate(x, 0), .rotate(degrees: r)) }
        return transforms(
            duration: 1.4,
            keyTimes: [0, 0.6, 0.66, 0.72, 0.78, 0.84, 0.9, 1],
            [f(0, 0), f(0, 0), f(-5, -3), f(5, 3), f(-4, -2), f(4, 2), f(-2, 0), f(0, 0)],
            timing: CSSTiming.easeInOut
        )
    }

    /// optik-yanson: 0.5s steps(2) (uyari "!").
    static func blinkMark() -> CAAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.duration = 0.5
        animation.calculationMode = .discrete
        // steps(2) over 1 → .25 and back: each half is split into two equal steps.
        animation.values = [1, 0.625, 0.25, 0.625]
        animation.keyTimes = [0, 0.25, 0.5, 0.75]
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// optik-parla: 0.5s ease-in-out alternate (kutlama eyes).
    static func sparkleEyes() -> CAAnimation {
        alternating("transform.scale", from: 0.8, to: 1.15, duration: 0.5, timing: CSSTiming.easeInOut)
    }

    static var hopTiming: CAMediaTimingFunction { CSSTiming.cubicBezier(0.3, 0.7, 0.4, 1) }

    /// optik-hopla: 0.72s (kutlama body).
    static func hop() -> CAAnimation {
        let rest = T.make(.translate(0, 0), .scale(1.06, 0.92))
        let top = T.make(.translate(0, -26), .scale(0.95, 1.07))
        let fall = T.make(.translate(0, -22), .scale(1, 1))
        return transforms(duration: 0.72, keyTimes: [0, 0.35, 0.6, 1], [rest, top, fall, rest], timing: hopTiming)
    }

    /// optik-golge-hopla: 0.72s (kutlama shadow).
    static func hopShadow() -> CAAnimation {
        let times: [Double] = [0, 0.35, 0.6, 1]
        let scale = transforms(duration: 0.72, keyTimes: times,
                               [T.make(.scale(1, 1)), T.make(.scale(0.66, 0.66)), T.make(.scale(0.7, 0.7)), T.make(.scale(1, 1))],
                               timing: hopTiming)
        let opacity = keyframes("opacity", duration: 0.72, keyTimes: times, values: [0.4, 0.22, 0.24, 0.4], timing: hopTiming)
        return group([scale, opacity], duration: 0.72)
    }

    /// optik-tekme-sol / -sag: 0.72s ease-in-out (kutlama legs). `degrees` is 30 or -30.
    static func kick(degrees: CGFloat) -> CAAnimation {
        let a = T.make(.rotate(degrees: 0)), b = T.make(.rotate(degrees: degrees))
        return transforms(duration: 0.72, keyTimes: [0, 0.4, 1], [a, b, a], timing: CSSTiming.easeInOut)
    }

    /// optik-pul: 0.9s ease-out (kutlama sparkles).
    static func sparkle() -> CAAnimation {
        let transform = transforms(duration: 0.9, keyTimes: [0, 1],
                                   [T.make(.scale(0.2, 0.2), .rotate(degrees: 45)),
                                    T.make(.scale(1.3, 1.3), .rotate(degrees: 45))],
                                   timing: CSSTiming.easeOut)
        let opacity = keyframes("opacity", duration: 0.9, keyTimes: [0, 0.3, 1], values: [0, 1, 0], timing: CSSTiming.easeOut)
        return group([transform, opacity], duration: 0.9)
    }

    /// optik-uyu: 3.6s ease-in-out (uykulu body sits down and breathes).
    static func sleepBreath() -> CAAnimation {
        let a = T.make(.translate(0, 36), .scale(1, 1))
        let b = T.make(.translate(0, 37), .scale(1.025, 0.975))
        return transforms(duration: 3.6, keyTimes: [0, 0.5, 1], [a, b, a], timing: CSSTiming.easeInOut)
    }

    /// The resting pose of `optik-uyu`, used when motion is reduced.
    static let sleepRest = T.make(.translate(0, 36))

    /// The resting pose of `optik-egil`, used when motion is reduced.
    static let leanRest = T.make(.rotate(degrees: -8))

    /// optik-merak: 2.4s ease-in-out (soru head tilt).
    static func curiousTilt() -> CAAnimation {
        let a = T.make(.rotate(degrees: -10)), b = T.make(.rotate(degrees: -6))
        return transforms(duration: 2.4, keyTimes: [0, 0.5, 1], [a, b, a], timing: CSSTiming.easeInOut)
    }

    /// The resting pose of `optik-merak`, used when motion is reduced.
    static let curiousRest = T.make(.rotate(degrees: -10))

    /// optik-soru: 1.6s ease-in-out (soru "?").
    static func questionBob() -> CAAnimation {
        let a = T.make(.translate(0, 0), .rotate(degrees: -8)), b = T.make(.translate(0, -4), .rotate(degrees: 8))
        return transforms(duration: 1.6, keyTimes: [0, 0.5, 1], [a, b, a], timing: CSSTiming.easeInOut)
    }

    /// optik-zz: 2.7s ease-in (uykulu letters).
    static func sleepLetter() -> CAAnimation {
        let transform = transforms(duration: 2.7, keyTimes: [0, 1],
                                   [T.make(.translate(0, 0), .scale(0.6, 0.6)),
                                    T.make(.translate(16, -34), .scale(1.2, 1.2))],
                                   timing: CSSTiming.easeIn)
        let opacity = keyframes("opacity", duration: 2.7, keyTimes: [0, 0.2, 1], values: [0, 1, 0], timing: CSSTiming.easeIn)
        return group([transform, opacity], duration: 2.7)
    }

    /// optik-zipla-a/b: 0.55s tap bounce. Plays once.
    static func bounce() -> CAAnimation {
        let animation = transforms(
            duration: 0.55,
            keyTimes: [0, 0.25, 0.55, 0.8, 1],
            [T.make(.scale(1, 1)),
             T.make(.scale(1.1, 0.86)),
             T.make(.scale(0.94, 1.08), .translate(0, -18)),
             T.make(.scale(1.03, 0.97)),
             T.make(.scale(1, 1))],
            timing: CSSTiming.cubicBezier(0.3, 0.7, 0.4, 1)
        )
        animation.repeatCount = 0
        animation.isRemovedOnCompletion = true
        return animation
    }
}
