import Testing
@testable import OptikCore

struct IslandStateMachineTests {
    private let reminder = Announcement(text: "Saat 13.00'te Yeliz ile kahve.")

    @Test func summonGreetsThenListens() {
        var island = IslandStateMachine()
        let r1 = island.handle(.summon)
        #expect(r1)
        #expect(island.phase == .wake)
        #expect(island.mood == .listening)
        island.handle(.greeted)
        #expect(island.phase == .listening)
        island.handle(.dismiss)
        #expect(island.phase == .idle)
    }

    @Test func greetedOnlyMovesOnFromWake() {
        var island = IslandStateMachine()
        let r2 = island.handle(.greeted)
        #expect(!r2)
        #expect(island.phase == .idle)
    }

    @Test func replyGrowsTheIslandAndCloses() {
        var island = IslandStateMachine()
        island.handle(.summon)
        island.handle(.greeted)
        island.handle(.reply("Ekledim."))
        #expect(island.phase == .replying)
        #expect(island.phase.size == DesignTokens.Island.reply)
        #expect(island.replyText == "Ekledim.")
        island.handle(.replyFinished)
        #expect(island.phase == .idle)
        #expect(island.replyText == nil)
    }

    @Test func replyWhileIdleIsIgnored() {
        var island = IslandStateMachine()
        let r3 = island.handle(.reply("x"))
        #expect(!r3)
    }

    @Test func announcementShowsWhenIdle() {
        var island = IslandStateMachine()
        island.handle(.announce(reminder))
        #expect(island.phase == .announcing)
        #expect(island.currentAnnouncement == reminder)
        #expect(island.mood == .alert)
        island.handle(.announcementFinished)
        #expect(island.phase == .idle)
    }

    @Test func fullScreenHoldsAnnouncementsUntilItEnds() {
        var island = IslandStateMachine()
        island.handle(.fullScreenChanged(true))
        #expect(!island.isVisible)
        island.handle(.announce(reminder))
        #expect(island.phase == .idle)
        #expect(island.pending == [reminder])
        #expect(!island.isVisible)
        island.handle(.fullScreenChanged(false))
        #expect(island.phase == .announcing)
        #expect(island.pending.isEmpty)
    }

    @Test func summonStillWorksInFullScreen() {
        var island = IslandStateMachine()
        island.handle(.fullScreenChanged(true))
        island.handle(.summon)
        #expect(island.phase == .wake)
        #expect(island.isVisible)
        island.handle(.dismiss)
        #expect(!island.isVisible)
    }

    @Test func announcementWaitsWhileTheUserTalks() {
        var island = IslandStateMachine()
        island.handle(.summon)
        island.handle(.announce(reminder))
        #expect(island.phase == .wake)
        island.handle(.dismiss)
        #expect(island.phase == .announcing)
        #expect(island.currentAnnouncement == reminder)
    }

    @Test func announcementsComeOneAtATime() {
        var island = IslandStateMachine()
        let second = Announcement(text: "Kuzey Mobilya ödemesi bugün.")
        island.handle(.announce(reminder))
        island.handle(.announce(second))
        #expect(island.currentAnnouncement == reminder)
        island.handle(.announcementFinished)
        #expect(island.currentAnnouncement == second)
        island.handle(.announcementFinished)
        #expect(island.phase == .idle)
    }

    @Test func summonOverAnAnnouncementCountsItAsSeen() {
        var island = IslandStateMachine()
        island.handle(.announce(reminder))
        island.handle(.summon)
        island.handle(.dismiss)
        #expect(island.phase == .idle)
        #expect(island.pending.isEmpty)
    }

    @Test func sizesMatchTokens() {
        #expect(IslandPhase.idle.size.width == 312)
        #expect(IslandPhase.wake.size.height == 150)
        #expect(IslandPhase.replying.size.width == 480)
        #expect(IslandPhase.allCases.filter(\.isOpen).count == 4)
    }
}

struct DoubleTapDetectorTests {
    @Test func quickDoubleTapFiresOnSecondPress() {
        var detector = DoubleTapDetector()
        let r4 = detector.handle(.down(at: 0))
        #expect(!r4)
        let r5 = detector.handle(.up(at: 0.08))
        #expect(!r5)
        let r6 = detector.handle(.down(at: 0.25))
        #expect(r6)
        let r7 = detector.handle(.up(at: 0.3))
        #expect(!r7)
    }

    @Test func slowSecondPressDoesNotFire() {
        var detector = DoubleTapDetector()
        detector.handle(.down(at: 0))
        detector.handle(.up(at: 0.1))
        let r8 = detector.handle(.down(at: 0.6))
        #expect(!r8)
    }

    @Test func holdingTheFirstPressDoesNotCount() {
        var detector = DoubleTapDetector()
        detector.handle(.down(at: 0))
        detector.handle(.up(at: 0.5))
        let r9 = detector.handle(.down(at: 0.6))
        #expect(!r9)
    }

    @Test func chordsInBetweenCancel() {
        // ⌘C then ⌘V quickly.
        var detector = DoubleTapDetector()
        detector.handle(.down(at: 0))
        detector.handle(.other)
        detector.handle(.up(at: 0.1))
        let r10 = detector.handle(.down(at: 0.2))
        #expect(!r10)
        detector.handle(.other)
        let r11 = detector.handle(.up(at: 0.25))
        #expect(!r11)
    }

    @Test func aSlowPressCanStartTheNextDoubleTap() {
        var detector = DoubleTapDetector()
        detector.handle(.down(at: 0))
        detector.handle(.up(at: 0.1))
        let r12 = detector.handle(.down(at: 1.0))
        #expect(!r12)
        detector.handle(.up(at: 1.05))
        let r13 = detector.handle(.down(at: 1.2))
        #expect(r13)
    }

    @Test func tripleTapFiresOnce() {
        var detector = DoubleTapDetector()
        detector.handle(.down(at: 0))
        detector.handle(.up(at: 0.05))
        let r14 = detector.handle(.down(at: 0.15))
        #expect(r14)
        detector.handle(.up(at: 0.2))
        let r15 = detector.handle(.down(at: 0.3))
        #expect(!r15)
    }
}
