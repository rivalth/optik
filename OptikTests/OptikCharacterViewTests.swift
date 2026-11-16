import OptikCore
import QuartzCore
import Testing
@testable import Optik

@MainActor
struct OptikCharacterViewTests {
    @Test(arguments: Mood.allCases)
    func everyMoodRunsLoops(mood: Mood) {
        let view = OptikCharacterView(frame: .zero)
        view.setMood(mood == .waiting ? .happy : .waiting, animated: false)
        view.setMood(mood, animated: true)
        #expect(view.mood == mood)
        #expect(view.loopAnimationCount > 0)
    }

    @Test(arguments: Mood.allCases)
    func reduceMotionStopsEveryLoop(mood: Mood) {
        let view = OptikCharacterView(frame: .zero)
        view.reduceMotion = true
        view.setMood(mood == .waiting ? .happy : .waiting, animated: false)
        view.setMood(mood, animated: true)
        #expect(view.loopAnimationCount == 0)
    }

    @Test func sleepyStillSitsDownWithReducedMotion() {
        let view = OptikCharacterView(frame: .zero)
        view.reduceMotion = true
        view.setMood(.sleepy, animated: false)
        #expect(view.swayTransformForTesting.m42 == 36)
    }

    @Test func eyesMoveWhenTheirWidthChanges() {
        let view = OptikCharacterView(frame: .zero)
        let waiting = view.leftEyePositionForTesting
        view.setMood(.alert, animated: false)
        // 12 wide eyes start 1 point further left than 10 wide ones.
        #expect(view.leftEyePositionForTesting.x == waiting.x - 1)
    }

    @Test func intrinsicSizeFollowsScale() {
        let view = OptikCharacterView(frame: .zero)
        view.scale = 2
        #expect(view.intrinsicContentSize == CGSize(width: 360, height: 400))
    }
}
