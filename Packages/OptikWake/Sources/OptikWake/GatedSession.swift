// Part of Optik (MIT). Works with code adapted from soniqo/speech-swift (Apache-2.0).

import Accelerate
import Foundation

// Optik: the encoder is the expensive part, so it runs only while there is sound
// clearly above the room. Everything that runs on every 20 ms frame here is
// constant time and allocation-free, because it runs all day.

/// Decides when audio is worth sending to the keyword spotter: open while the
/// level rises above both the room's floor and its background, closed after a
/// stretch without such sound.
public struct SoundGate: Sendable {
    public struct Configuration: Sendable {
        /// Above the quietest 100 ms block of the last `floorBlocks`.
        public var floorMargin: Double = 10
        /// Above the background: the loud end (`backgroundPercentile`) of the last
        /// `backgroundFrames`. All frames count, so a film becomes background; a
        /// wake word is too short to move it.
        public var backgroundMargin: Double = 6
        public var backgroundFrames = 300
        public var backgroundPercentile = 0.9
        /// Quieter than this never opens the gate.
        public var minimumLevel: Double = -60
        public var openFrames = 3
        public var closeAfterFrames = 60
        public var floorBlocks = 30
        public init() {}
    }

    public var configuration: Configuration
    public private(set) var isOpen = false
    public private(set) var background: Double = -100
    public private(set) var floor: Double = -100

    // Background: a ring of level bins and a histogram of them (0.5 dB bins).
    private var ring: [UInt8]
    private var ringIndex = 0
    private var ringCount = 0
    private var histogram = [Int](repeating: 0, count: 201)
    // Floor: minimum level per 100 ms block, in a ring.
    private var blocks: [Double]
    private var blockIndex = 0
    private var blockMin = Double.infinity
    private var blockFrames = 0
    private var loudFrames = 0
    private var framesSinceLoud = Int.max / 2
    private var frameCount = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        ring = [UInt8](repeating: 0, count: configuration.backgroundFrames)
        blocks = [Double](repeating: .infinity, count: configuration.floorBlocks)
    }

    /// One 20 ms frame's level in dBFS. Returns true when the gate opens.
    public mutating func process(level: Double) -> Bool {
        let config = configuration
        frameCount += 1
        trackFloor(level)
        trackBackground(level)

        let threshold = max(floor + config.floorMargin, background + config.backgroundMargin, config.minimumLevel)
        let loud = level > threshold
        framesSinceLoud = loud ? 0 : framesSinceLoud + 1

        if isOpen {
            if framesSinceLoud >= config.closeAfterFrames {
                isOpen = false
                loudFrames = 0
            }
            return false
        }
        loudFrames = loud ? loudFrames + 1 : 0
        guard loudFrames >= config.openFrames else { return false }
        isOpen = true
        return true
    }

    private mutating func trackFloor(_ level: Double) {
        blockMin = min(blockMin, level)
        blockFrames += 1
        guard blockFrames == 5 else { return }
        blocks[blockIndex] = blockMin
        blockIndex = (blockIndex + 1) % blocks.count
        blockMin = .infinity
        blockFrames = 0
        floor = blocks.min() ?? -100
    }

    private mutating func trackBackground(_ level: Double) {
        let bin = UInt8(max(0, min(200, Int(((level + 100) * 2).rounded()))))
        if ringCount == ring.count {
            histogram[Int(ring[ringIndex])] -= 1
        } else {
            ringCount += 1
        }
        ring[ringIndex] = bin
        histogram[Int(bin)] += 1
        ringIndex = (ringIndex + 1) % ring.count
        // The percentile moves slowly; five times a second is plenty.
        guard frameCount % 10 == 0 else { return }
        let target = Int(Double(ringCount - 1) * configuration.backgroundPercentile)
        var seen = 0
        for (index, count) in histogram.enumerated() {
            seen += count
            if seen > target {
                background = Double(index) / 2 - 100
                return
            }
        }
    }
}

/// A keyword session behind a `SoundGate`, with a pre-roll so the start of the
/// word is not lost while the gate was closed.
public final class GatedWakeWordSession {
    public static let frameLength = 320
    public static let preRollFrames = 40   // 0.8 s

    private let session: WakeWordSession
    public private(set) var gate: SoundGate
    private var pending: [Float] = []
    private var preRoll: [Float]
    private var preRollIndex = 0
    private var preRollFilled = 0
    /// Seconds of audio sent to the model, for measuring.
    public private(set) var processedSeconds: Double = 0

    public init(detector: WakeWordDetector, gate: SoundGate = SoundGate()) throws {
        session = try detector.createSession()
        self.gate = gate
        preRoll = [Float](repeating: 0, count: Self.preRollFrames * Self.frameLength)
        pending.reserveCapacity(4_800)
    }

    public func pushAudio(_ samples: [Float]) throws -> [KeywordDetection] {
        pending.append(contentsOf: samples)
        var detections: [KeywordDetection] = []
        var start = 0
        while pending.count - start >= Self.frameLength {
            let range = start..<(start + Self.frameLength)
            start += Self.frameLength
            let wasOpen = gate.isOpen
            let level = pending.withUnsafeBufferPointer { Self.level(of: UnsafeBufferPointer(rebasing: $0[range])) }
            let opened = gate.process(level: level)
            if opened {
                try session.reset()
                var audio = orderedPreRoll()
                audio.append(contentsOf: pending[range])
                processedSeconds += Double(audio.count) / 16_000
                detections += try session.pushAudio(audio)
                preRollFilled = 0
            } else if gate.isOpen {
                processedSeconds += Double(Self.frameLength) / 16_000
                detections += try session.pushAudio(Array(pending[range]))
            } else {
                if wasOpen { detections += try session.finalize() }
                storePreRoll(range)
            }
        }
        pending.removeFirst(start)
        return detections
    }

    private func storePreRoll(_ range: Range<Int>) {
        let offset = preRollIndex * Self.frameLength
        pending.withUnsafeBufferPointer { source in
            preRoll.withUnsafeMutableBufferPointer { target in
                target.baseAddress!.advanced(by: offset).update(from: source.baseAddress!.advanced(by: range.lowerBound), count: Self.frameLength)
            }
        }
        preRollIndex = (preRollIndex + 1) % Self.preRollFrames
        preRollFilled = min(preRollFilled + 1, Self.preRollFrames)
    }

    private func orderedPreRoll() -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(preRollFilled * Self.frameLength + Self.frameLength)
        let first = (preRollIndex - preRollFilled + Self.preRollFrames) % Self.preRollFrames
        for i in 0..<preRollFilled {
            let frame = (first + i) % Self.preRollFrames
            result.append(contentsOf: preRoll[(frame * Self.frameLength)..<((frame + 1) * Self.frameLength)])
        }
        return result
    }

    static func level(of frame: UnsafeBufferPointer<Float>) -> Double {
        var meanSquare: Float = 0
        vDSP_measqv(frame.baseAddress!, 1, &meanSquare, vDSP_Length(frame.count))
        return meanSquare > 0 ? max(-100, 10 * log10(Double(meanSquare))) : -100
    }
}
