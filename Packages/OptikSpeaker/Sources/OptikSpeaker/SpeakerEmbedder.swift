import FluidAudio
import Foundation

/// Turns a stretch of speech into a voice fingerprint: a 192-number vector that is
/// close (cosine similarity) for the same speaker and far for others. Runs on the
/// device; the model (CAM++, about 30 MB) is downloaded once from Hugging Face.
public actor SpeakerEmbedder {
    private var embedder: CampPlusEmbedder?

    public init() {}

    /// Whether the model is already on disk.
    public static var isDownloaded: Bool {
        CampPlusModels.modelsExist(at: modelFolder)
    }

    private static var modelFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Optik/Models/speaker", directoryHint: .isDirectory)
    }

    /// Downloads the model if needed and loads it. Cheap when it is loaded.
    public func prepare() async throws {
        guard embedder == nil else { return }
        let folder = Self.modelFolder
        if !CampPlusModels.modelsExist(at: folder) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let downloaded = try await CampPlusModels.download()
            // FluidAudio downloads into its own folder; keep Optik's models together.
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.copyItem(at: downloaded, to: folder)
        }
        embedder = CampPlusEmbedder(models: try CampPlusModels.load(from: folder))
    }

    /// `samples`: 16 kHz mono, -1...1, at least half a second of speech.
    public func embedding(of samples: [Float]) async throws -> [Float] {
        try await prepare()
        guard let embedder else { throw SpeakerError.notLoaded }
        return try await embedder.embed(audio: samples)
    }

    public func unload() {
        embedder = nil
    }
}

public enum SpeakerError: Error {
    case notLoaded
}
