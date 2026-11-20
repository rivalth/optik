import AVFoundation
import Foundation
import OptikCore
import OptikSpeaker
import os

/// Tells the user's voice from others (Settings → Çağırma → "Sesimi tanı"). With a
/// profile and the setting on, "Optik" from someone else does not wake Optik, and
/// in a conversation other people's sentences are not taken as the user's.
///
/// Only the fingerprint numbers are stored (`speaker-profile.json`), never audio.
actor SpeakerVerifier {
    static let shared = SpeakerVerifier()

    /// Audio from the conversation's microphone goes through echo cancellation,
    /// unlike the samples, so it gets a slightly lower bar.
    static let conversationLeniency: Float = 0.1
    /// Fingerprints of shorter audio say too little; such audio is let through.
    static let shortestCheckedAudio = 8_000

    private let embedder = SpeakerEmbedder()
    private(set) var profile: SpeakerProfile?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Optik", category: "speaker")

    init() {
        profile = Self.loadProfile()
    }

    static var profileURL: URL {
        ModelStorage.base.deletingLastPathComponent().appending(path: "speaker-profile.json")
    }

    nonisolated static var hasProfile: Bool {
        FileManager.default.fileExists(atPath: profileURL.path)
    }

    /// Checking is on when there is a profile and the user did not turn it off.
    nonisolated static var isEnabled: Bool {
        hasProfile && (UserDefaults.standard.object(forKey: SettingsKey.onlyMyVoice) as? Bool ?? true)
    }

    /// Loads the model ahead of the first check.
    func prepare() async {
        guard Self.isEnabled else { return }
        do { try await embedder.prepare() } catch { log.error("speaker model could not be loaded") }
    }

    /// Whether `samples` (16 kHz) are the user's voice. True when checking is off,
    /// the audio is too short to judge, or the model fails: never lock the user out.
    func isUser(_ samples: [Float], leniency: Float = 0, context: String) async -> Bool {
        guard Self.isEnabled, let profile, samples.count >= Self.shortestCheckedAudio else { return true }
        let started = ContinuousClock.now
        do {
            let embedding = try await embedder.embedding(of: samples)
            let similarity = profile.similarity(to: embedding)
            let match = similarity >= profile.threshold - leniency
            let elapsed = started.duration(to: .now).components
            let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
            log.info("""
                \(context, privacy: .public): similarity \(similarity, format: .fixed(precision: 2), privacy: .public) \
                (bar \(profile.threshold - leniency, format: .fixed(precision: 2), privacy: .public)) in \(ms, privacy: .public) ms: \
                \(match ? "user" : "someone else", privacy: .public)
                """)
            return match
        } catch {
            log.error("speaker check failed")
            return true
        }
    }

    // MARK: Enrollment

    /// Builds and saves a profile from the user's recorded samples.
    func enroll(_ recordings: [[Float]]) async throws -> SpeakerProfile {
        try await embedder.prepare()
        var embeddings: [[Float]] = []
        for recording in recordings where recording.count >= 4_000 {
            embeddings.append(try await embedder.embedding(of: recording))
        }
        guard let profile = SpeakerProfile(samples: embeddings) else { throw EnrollmentError.tooFewSamples }
        let data = try JSONEncoder().encode(profile)
        try FileManager.default.createDirectory(at: Self.profileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: Self.profileURL, options: .atomic)
        self.profile = profile
        let similarities = embeddings.map { profile.similarity(to: $0) }
        log.info("profile saved: \(embeddings.count, privacy: .public) samples, threshold \(profile.threshold, format: .fixed(precision: 2), privacy: .public), sample similarities \(similarities.map { String(format: "%.2f", $0) }.joined(separator: " "), privacy: .public)")
        return profile
    }

    func removeProfile() {
        try? FileManager.default.removeItem(at: Self.profileURL)
        profile = nil
        Task { await embedder.unload() }
    }

    private static func loadProfile() -> SpeakerProfile? {
        guard let data = try? Data(contentsOf: profileURL) else { return nil }
        return try? JSONDecoder().decode(SpeakerProfile.self, from: data)
    }

    enum EnrollmentError: Error {
        case tooFewSamples
    }
}
