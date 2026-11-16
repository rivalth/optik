import AVFoundation

/// Says "Efendim?" with a Turkish system voice until Optik has its own voice
/// (Stage 1 of `docs/04-yol-haritasi.md`).
@MainActor
final class GreetingSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "tr-TR")

    var hasVoice: Bool { voice != nil }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// The first utterance loads the voice; do it silently at launch so the real one
    /// starts without that delay.
    func prewarm() {
        guard let voice else { return }
        let utterance = AVSpeechUtterance(string: " ")
        utterance.voice = voice
        utterance.volume = 0
        synthesizer.speak(utterance)
    }

    func speak(_ text: String) {
        guard let voice else { onFinish?(); return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // Same character as the design demo: higher and a bit quicker than normal.
        utterance.pitchMultiplier = 1.6
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard utterance.volume > 0 else { return }
        Task { @MainActor in self.onStart?() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance.volume > 0 else { return }
        Task { @MainActor in self.onFinish?() }
    }
}
