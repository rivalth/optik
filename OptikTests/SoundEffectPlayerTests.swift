import AVFoundation
import OptikCore
import Testing
@testable import Optik

struct SoundEffectPlayerTests {
    @Test func everyEffectIsBundledAndDecodes() async {
        let player = SoundEffectPlayer()
        await player.preload()
        #expect(await player.loadedEffects == Set(SoundEffect.allCases))
    }

    @Test(arguments: SoundEffect.allCases)
    func effectsAreMono44k(effect: SoundEffect) async throws {
        let player = SoundEffectPlayer()
        await player.preload()
        let format = try #require(await player.format(of: effect))
        #expect(format.sampleRate == 44_100)
        #expect(format.channelCount == 1)
    }

    @Test func speechFolderReadmeIsNotBundled() {
        #expect(Bundle.main.url(forResource: "OKU", withExtension: "txt") == nil)
    }
}
