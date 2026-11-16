import AVFoundation

/// The system's Turkish voice. Only a fallback: when there is no network or no
/// ElevenLabs key (`docs/02-mimari.md` 3.4). It is not Optik's character voice.
@MainActor
final class SystemSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    /// The best Turkish voice installed: premium or enhanced when the user has
    /// downloaded one, the small built-in voice otherwise.
    private let voice = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language == "tr-TR" }
        .max { $0.quality.rawValue < $1.quality.rawValue }
        ?? AVSpeechSynthesisVoice(language: "tr-TR")
    private var waiting: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    var onStart: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// The first utterance loads the voice; do it silently at launch.
    func prewarm() {
        guard let voice else { return }
        let utterance = AVSpeechUtterance(string: " ")
        utterance.voice = voice
        utterance.volume = 0
        synthesizer.speak(utterance)
    }

    /// Speaks and returns when done or stopped.
    func speak(_ text: String) async {
        guard let voice else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // Same character as the design demo: higher and a bit quicker than normal.
        utterance.pitchMultiplier = 1.6
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        await withCheckedContinuation { continuation in
            waiting[ObjectIdentifier(utterance)] = continuation
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func finished(_ utterance: AVSpeechUtterance) {
        waiting.removeValue(forKey: ObjectIdentifier(utterance))?.resume()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let audible = utterance.volume > 0
        Task { @MainActor in if audible { self.onStart?() } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.waiting.removeValue(forKey: id)?.resume() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.waiting.removeValue(forKey: id)?.resume() }
    }
}
