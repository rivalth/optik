import Foundation
import OptikCore
import os

/// Runs the endpoint detector on microphone frames and keeps the current utterance,
/// with a short pre-roll so the first syllable is not cut off. Lives on the audio
/// queue; the main actor only reads snapshots.
final class UtteranceRecorder: @unchecked Sendable {
    /// 0.3 s of audio before speech was detected.
    static let preRollSamples = 4_800

    private struct State {
        var detector = EndpointDetector()
        var preRoll: [Float] = []
        var utterance: [Float] = []
        var isRecording = false
        /// Bumped on every new utterance, so stale partial transcripts are dropped.
        var utteranceID = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let onEvent: @Sendable (EndpointDetector.Event, Int) -> Void

    init(onEvent: @escaping @Sendable (EndpointDetector.Event, Int) -> Void) {
        self.onEvent = onEvent
    }

    #if DEBUG
    private let debugLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "vad")
    private let stats = OSAllocatedUnfairLock(initialState: (frames: 0, peak: -100.0))
    #endif

    func process(_ frame: [Float], at time: Double) {
        let level = EndpointDetector.level(of: frame)
        #if DEBUG
        // Once a second: how loud the room is and where the noise floor sits.
        let report: (Int, Double)? = stats.withLock { stats in
            stats.frames += 1
            stats.peak = max(stats.peak, level)
            guard stats.frames % 50 == 0 else { return nil }
            defer { stats.peak = -100 }
            return (stats.frames, stats.peak)
        }
        if let report {
            let (floor, background) = state.withLock { ($0.detector.noiseFloor, $0.detector.background) }
            debugLog.debug("frames \(report.0) peak \(report.1, format: .fixed(precision: 1)) dB floor \(floor, format: .fixed(precision: 1)) dB background \(background, format: .fixed(precision: 1)) dB")
        }
        #endif
        let result: (EndpointDetector.Event, Int)? = state.withLock { state in
            if state.isRecording {
                state.utterance.append(contentsOf: frame)
            } else {
                state.preRoll.append(contentsOf: frame)
                if state.preRoll.count > Self.preRollSamples {
                    state.preRoll.removeFirst(state.preRoll.count - Self.preRollSamples)
                }
            }
            guard let event = state.detector.process(level: level, at: time) else { return nil }
            switch event {
            case .speechStarted:
                state.utteranceID += 1
                state.isRecording = true
                state.utterance = state.preRoll
                state.preRoll.removeAll(keepingCapacity: true)
            case .speechEnded:
                state.isRecording = false
            }
            return (event, state.utteranceID)
        }
        if let result { onEvent(result.0, result.1) }
    }

    var isSpeaking: Bool { state.withLock { $0.isRecording } }

    /// Seconds of the current utterance clearly above the room.
    var strongSpeech: Double { state.withLock { $0.detector.strongSpeech } }

    /// The utterance so far, for a partial transcript.
    func snapshot() -> (samples: [Float], id: Int) {
        state.withLock { ($0.utterance, $0.utteranceID) }
    }

    /// Forgets everything but the room's noise floor.
    func reset() {
        state.withLock { state in
            state.utterance.removeAll()
            state.preRoll.removeAll()
            state.isRecording = false
            state.utteranceID += 1
        }
    }

    /// A fresh detector, for a new conversation in a possibly different room.
    func resetDetector() {
        state.withLock { state in
            state = State(utteranceID: state.utteranceID + 1)
        }
    }
}
