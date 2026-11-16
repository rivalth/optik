import AVFoundation
import OptikCore
import os

/// Plays the character's sound effects with no decoding at play time.
///
/// Buffers are decoded once, off the main thread. The audio engine only runs while
/// something is playing and stops after a short idle period, so it costs nothing at rest.
actor SoundEffectPlayer {
    static let shared = SoundEffectPlayer()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var idleStopTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "optik", category: "sound")

    /// Simultaneous sounds (a tap during a mood change, for example).
    private static let voiceCount = 3
    private static let idleStopDelay: Duration = .seconds(3)

    var isEnabled = true

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { stopAll() }
    }

    /// Decodes every effect. Safe to call more than once.
    func preload() {
        guard buffers.isEmpty else { return }
        for effect in SoundEffect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else {
                logger.error("missing sound effect \(effect.rawValue, privacy: .public)")
                continue
            }
            do {
                let file = try AVAudioFile(forReading: url)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)) else { continue }
                try file.read(into: buffer)
                buffers[effect] = buffer
            } catch {
                logger.error("cannot read sound effect \(effect.rawValue, privacy: .public)")
            }
        }
        guard let format = buffers.values.first?.format else { return }
        for _ in 0..<Self.voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.prepare()
    }

    func play(_ effect: SoundEffect) {
        guard isEnabled else { return }
        preload()
        guard let buffer = buffers[effect], !players.isEmpty else { return }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            logger.error("audio engine did not start")
            return
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
        scheduleIdleStop(after: Double(buffer.frameLength) / buffer.format.sampleRate)
    }

    var loadedEffects: Set<SoundEffect> { Set(buffers.keys) }

    func format(of effect: SoundEffect) -> AVAudioFormat? { buffers[effect]?.format }

    private func scheduleIdleStop(after seconds: Double) {
        idleStopTask?.cancel()
        idleStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds) + Self.idleStopDelay)
            guard !Task.isCancelled else { return }
            await self?.stopAll()
        }
    }

    private func stopAll() {
        idleStopTask?.cancel()
        for player in players { player.stop() }
        if engine.isRunning { engine.stop() }
    }
}
