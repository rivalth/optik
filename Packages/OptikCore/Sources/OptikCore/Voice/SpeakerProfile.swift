import Foundation

/// The user's voice fingerprint, from a few samples recorded in Settings. Only
/// these numbers are kept, never the recordings.
///
/// Two fingerprints of the same voice point the same way (cosine similarity near
/// 1); other voices point elsewhere. The threshold comes from the samples
/// themselves: a little below how alike the user's own samples were.
public struct SpeakerProfile: Codable, Equatable, Sendable {
    /// The mean of the samples' fingerprints, unit length.
    public var centroid: [Float]
    /// Similarity at or above this is the user.
    public var threshold: Float
    public var createdAt: Date

    /// Never stricter than this: short words give noisy fingerprints.
    public static let highestThreshold: Float = 0.5
    /// Never looser than this: other voices start to pass.
    public static let lowestThreshold: Float = 0.3
    /// How far below the samples' weakest match to the centroid the threshold sits.
    public static let margin: Float = 0.1

    public init(centroid: [Float], threshold: Float, createdAt: Date = .now) {
        self.centroid = centroid
        self.threshold = threshold
        self.createdAt = createdAt
    }

    /// Builds a profile from fingerprints of the user's samples. Needs at least three.
    public init?(samples: [[Float]], createdAt: Date = .now) {
        guard samples.count >= 3, let length = samples.first?.count, length > 0,
              samples.allSatisfy({ $0.count == length })
        else { return nil }
        var sum = [Float](repeating: 0, count: length)
        for sample in samples {
            let unit = Self.normalized(sample)
            for i in 0..<length { sum[i] += unit[i] }
        }
        let centroid = Self.normalized(sum)
        let weakest = samples.map { Self.similarity(centroid, $0) }.min() ?? 0
        let threshold = min(max(weakest - Self.margin, Self.lowestThreshold), Self.highestThreshold)
        self.init(centroid: centroid, threshold: threshold, createdAt: createdAt)
    }

    /// How much a fingerprint sounds like the user, -1...1.
    public func similarity(to embedding: [Float]) -> Float {
        Self.similarity(centroid, embedding)
    }

    /// Whether a fingerprint is the user. `leniency` lowers the bar, for audio that
    /// went through other processing than the samples (the conversation's echo
    /// cancellation).
    public func matches(_ embedding: [Float], leniency: Float = 0) -> Bool {
        similarity(to: embedding) >= threshold - leniency
    }

    public static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let norm = (na * nb).squareRoot()
        return norm > 0 ? dot / norm : -1
    }

    private static func normalized(_ v: [Float]) -> [Float] {
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? v.map { $0 / norm } : v
    }
}
