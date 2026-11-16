import Foundation

/// Finds where the user starts and stops talking, from the loudness of short audio
/// frames (voice activity detection, `docs/02-mimari.md` 3).
///
/// The noise floor is the quietest moment of the last `floorWindow` seconds, so it
/// follows the room up and down, also while the user talks: the short gaps between
/// words keep it near the room. Speech starts after `startDuration` above the floor
/// and ends after `endSilence` near it.
///
/// A video or a conversation in the room is speech too, so the floor alone is not
/// enough. The background is the loud end (`backgroundPercentile`) of the last few
/// seconds before the user spoke; the user, closer to the microphone, must rise
/// above it, and falling back into it ends the sentence.
public struct EndpointDetector: Sendable {
    public enum Event: Equatable, Sendable {
        case speechStarted(at: Double)
        case speechEnded(at: Double)
    }

    public struct Configuration: Sendable, Equatable {
        /// Speech must be this many dB above the noise floor to start.
        public var startMargin: Double = 12
        /// Below this many dB above the floor counts as silence again.
        public var endMargin: Double = 8
        /// Speech this many dB above the floor counts as clearly addressed to Optik,
        /// for talking over its reply (see `strongSpeech`).
        public var strongMargin: Double = 20
        /// Quieter than this is never speech, however quiet the room.
        public var minimumSpeechLevel: Double = -50
        public var startDuration: Double = 0.12
        /// The pause that ends a sentence. Long enough for a breath, short enough
        /// to keep the reply fast.
        public var endSilence: Double = 0.7
        /// One utterance never runs longer than this.
        public var maximumUtterance: Double = 30
        /// How far back the floor looks for the room's quietest moment. Longer than
        /// any sound in speech without a gap.
        public var floorWindow: Double = 2
        /// The floor never sinks below this: real rooms are not this quiet.
        public var lowestNoiseFloor: Double = -75
        /// Speech also ends when it drops this far below its own loudest part.
        public var dropFromPeak: Double = 20
        /// Smoothing of frame levels, 0...1. Higher follows faster.
        public var smoothing: Double = 0.5
        /// How many recent quiet frames describe the background (20 ms each).
        public var backgroundFrames: Int = 200
        /// The background is this loud end of those frames, 0...1.
        public var backgroundPercentile: Double = 0.9
        /// Speech must start this many dB above the background.
        public var backgroundStartMargin: Double = 6
        /// Clearly addressed speech is this many dB above the background.
        public var backgroundStrongMargin: Double = 12
        /// Back within this many dB of the background counts as silence.
        public var backgroundEndMargin: Double = 3

        public init() {}
    }

    public var configuration: Configuration
    public private(set) var noiseFloor: Double = -100
    public private(set) var isSpeaking = false
    public private(set) var speechStart: Double?
    /// Seconds of the current utterance at least `strongMargin` above the floor.
    public private(set) var strongSpeech: Double = 0
    /// The loud end of the room before the current utterance, in dBFS.
    public private(set) var background: Double = -100

    private var aboveSince: Double?
    private var belowSince: Double?
    private var speechPeak: Double = -100
    private var smoothed: Double?
    private var lastTime: Double?
    /// Recent smoothed levels, oldest first, for the floor.
    private var recent: [(time: Double, level: Double)] = []
    /// Smoothed levels of recent frames outside speech, oldest first.
    private var quiet: [Double] = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Feeds one frame: its level in dBFS and the time at its end, in seconds.
    public mutating func process(level rawLevel: Double, at time: Double) -> Event? {
        let config = configuration
        // Digital silence (a microphone starting up) says nothing about the room.
        guard rawLevel > -95 else { return nil }
        let level = smoothed.map { $0 + (rawLevel - $0) * config.smoothing } ?? rawLevel
        smoothed = level
        let frameDuration = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 0
        lastTime = time
        updateFloor(with: level, at: time)

        let silence = max(noiseFloor + config.endMargin, background + config.backgroundEndMargin)
        if isSpeaking {
            speechPeak = max(speechPeak, level)
            if level >= strongLevel { strongSpeech += frameDuration }
            if level < silence || level < speechPeak - config.dropFromPeak {
                if belowSince == nil { belowSince = time }
            } else {
                belowSince = nil
            }
            let silent = belowSince.map { time - $0 >= config.endSilence } ?? false
            let tooLong = speechStart.map { time - $0 >= config.maximumUtterance } ?? false
            if silent || tooLong {
                isSpeaking = false
                aboveSince = nil
                belowSince = nil
                return .speechEnded(at: time)
            }
            return nil
        }

        let start = max(noiseFloor + config.startMargin, background + config.backgroundStartMargin, config.minimumSpeechLevel)
        guard level > start else {
            aboveSince = nil
            updateBackground(with: level)
            return nil
        }
        if aboveSince == nil { aboveSince = time }
        guard let since = aboveSince, time - since >= config.startDuration else { return nil }
        isSpeaking = true
        belowSince = nil
        speechPeak = level
        speechStart = since
        strongSpeech = level >= strongLevel ? time - since : 0
        return .speechStarted(at: since)
    }

    private var strongLevel: Double {
        max(noiseFloor + configuration.strongMargin, background + configuration.backgroundStrongMargin)
    }

    /// The loud end of the recent frames that were not speech.
    private mutating func updateBackground(with level: Double) {
        quiet.append(level)
        if quiet.count > configuration.backgroundFrames { quiet.removeFirst(quiet.count - configuration.backgroundFrames) }
        let sorted = quiet.sorted()
        let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * configuration.backgroundPercentile))
        background = sorted[index]
    }

    /// The quietest smoothed level of the last `floorWindow` seconds.
    private mutating func updateFloor(with level: Double, at time: Double) {
        recent.append((time, level))
        let cutoff = time - configuration.floorWindow
        if let first = recent.firstIndex(where: { $0.time >= cutoff }), first > 0 {
            recent.removeFirst(first)
        }
        let quietest = recent.lazy.map(\.level).min() ?? level
        noiseFloor = max(quietest, configuration.lowestNoiseFloor)
    }

    /// Root mean square level in dBFS of samples in -1...1. Silence is -100.
    public static func level(of samples: some Collection<Float>) -> Double {
        guard !samples.isEmpty else { return -100 }
        var sum: Double = 0
        for sample in samples { sum += Double(sample) * Double(sample) }
        let rms = (sum / Double(samples.count)).squareRoot()
        return rms > 0 ? max(-100, 20 * log10(rms)) : -100
    }
}

/// Short phrases that end a turn on the spot, without asking the LLM
/// (`docs/02-mimari.md` 3.5).
public enum LocalCommand: Equatable, Sendable {
    /// "tamam", "sus", "boş ver", "vazgeç", "iptal"
    case stop

    private static let stopPhrases: Set<String> = [
        "tamam", "tamamdır", "sus", "boş ver", "boşver", "vazgeç", "vazgeçtim", "iptal", "kapat", "yok bir şey", "hiç",
    ]

    /// Matches the whole utterance only, so "tamam, yarın 3'te Yeliz" still goes to the LLM.
    public init?(_ transcript: String) {
        let words = transcript
            .lowercased(with: Locale(identifier: "tr_TR"))
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let withoutName = words.hasPrefix("optik ") ? String(words.dropFirst(6)) : words
        guard Self.stopPhrases.contains(withoutName) else { return nil }
        self = .stop
    }
}
