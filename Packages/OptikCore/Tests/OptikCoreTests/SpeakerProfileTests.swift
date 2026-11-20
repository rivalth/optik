import Foundation
import OptikCore
import Testing

struct SpeakerProfileTests {
    /// A voice: a direction plus a little noise per sample.
    private func samples(of voice: [Float], count: Int, noise: Float, seed: Int) -> [[Float]] {
        (0..<count).map { n in
            voice.enumerated().map { i, v in v + noise * sin(Float(i * 7 + n * 13 + seed)) }
        }
    }

    private let user: [Float] = (0..<192).map { sin(Float($0) * 0.37) }
    private let other: [Float] = (0..<192).map { cos(Float($0) * 0.91 + 1) }

    @Test func recognizesTheUserAndNotSomeoneElse() throws {
        let profile = try #require(SpeakerProfile(samples: samples(of: user, count: 8, noise: 0.3, seed: 0)))
        for sample in samples(of: user, count: 5, noise: 0.3, seed: 99) {
            #expect(profile.matches(sample))
        }
        for sample in samples(of: other, count: 5, noise: 0.3, seed: 5) {
            #expect(!profile.matches(sample))
        }
    }

    @Test func thresholdStaysWithinBounds() throws {
        let tight = try #require(SpeakerProfile(samples: samples(of: user, count: 5, noise: 0.01, seed: 1)))
        #expect(tight.threshold == SpeakerProfile.highestThreshold)
        let loose = try #require(SpeakerProfile(samples: samples(of: user, count: 5, noise: 3, seed: 2)))
        #expect(loose.threshold >= SpeakerProfile.lowestThreshold)
    }

    @Test func needsThreeSamples() {
        #expect(SpeakerProfile(samples: [user, user]) == nil)
        #expect(SpeakerProfile(samples: [user, user, [1, 2]]) == nil)
    }

    @Test func survivesASaveAndLoad() throws {
        let profile = try #require(SpeakerProfile(samples: samples(of: user, count: 4, noise: 0.2, seed: 3)))
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(SpeakerProfile.self, from: data) == profile)
    }
}
