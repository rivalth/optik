@preconcurrency import AVFoundation
import Foundation
import OptikCore
import Speech

/// Apple's dictation model, on this Mac (`docs/02-mimari.md` 3.2). macOS 26's
/// `SpeechTranscriber` has no Turkish; `DictationTranscriber` does. Its language
/// files come with the system's dictation and are installed once.
@available(macOS 26, *)
enum AppleDictation {
    static let locale = Locale(identifier: "tr-TR")

    private static func module() -> DictationTranscriber {
        DictationTranscriber(locale: locale, preset: .shortDictation)
    }

    static func isInstalled() async -> Bool {
        await AssetInventory.status(forModules: [module()]) == .installed
    }

    static func isSupported() async -> Bool {
        await DictationTranscriber.supportedLocale(equivalentTo: locale) != nil
    }

    /// Downloads Turkish dictation if the system does not have it yet.
    static func install() async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module()]) {
            try await request.downloadAndInstall()
        }
    }

    /// `samples`: 16 kHz mono, -1...1. `hints`: names and terms it may not expect.
    static func transcribe(_ samples: [Float], hints: [String]) async throws -> String {
        let transcriber = module()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let buffer = Self.buffer(samples, in: format) else { throw DictationError.audioFormat }
        let context = AnalysisContext()
        context.contextualStrings[.general] = hints
        let (input, feed) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(inputSequence: input, modules: [transcriber], analysisContext: context)
        let results = Task {
            var text = ""
            for try await result in transcriber.results { text += String(result.text.characters) }
            return text
        }
        feed.yield(AnalyzerInput(buffer: buffer))
        feed.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            results.cancel()
            throw error
        }
        return TranscriptFilter.clean(try await results.value)
    }

    /// The samples converted to what the analyzer wants (usually 16-bit 16 kHz).
    private static func buffer(_ samples: [Float], in format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        if format == source { return input }
        guard let converter = AVAudioConverter(from: source, to: format) else { return nil }
        let capacity = AVAudioFrameCount(Double(samples.count) * format.sampleRate / 16_000) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        // The converter asks for input until told the stream ended; it gets the one buffer once.
        let pending = PendingBuffer(input)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard let buffer = pending.take() else { status.pointee = .endOfStream; return nil }
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }
}

/// One buffer handed over once; the converter calls back on its own thread.
private final class PendingBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    private let lock = NSLock()

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        lock.withLock { defer { buffer = nil }; return buffer }
    }
}

enum DictationError: Error {
    case audioFormat
}
