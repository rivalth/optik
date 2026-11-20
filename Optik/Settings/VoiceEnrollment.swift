@preconcurrency import AVFoundation
import Observation
import OptikCore
import os
import SwiftUI

/// Records one sample of the user's voice for the speaker profile: starts when the
/// user starts talking, stops after a short pause. Its own microphone engine, like
/// the wake word listener's, so the samples sound like what that listener hears.
final class EnrollmentRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "optik.enrollment", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var detector = EndpointDetector()
    private var samples: [Float] = []
    private var speechStart: Int?
    private var pending: [Float] = []
    private var continuation: CheckedContinuation<[Float]?, Never>?

    /// Waits up to `timeout` seconds for the user to say something; nil if they did not.
    func record(timeout: Double = 8) async -> [Float]? {
        await withCheckedContinuation { continuation in
            queue.async { self.start(continuation, timeout: timeout) }
        }
    }

    func cancel() {
        queue.async { self.finish(nil) }
    }

    private func start(_ continuation: CheckedContinuation<[Float]?, Never>, timeout: Double) {
        self.continuation = continuation
        detector = EndpointDetector()
        samples.removeAll()
        pending.removeAll()
        speechStart = nil
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: VoiceAudio.captureFormat) else {
            finish(nil)
            return
        }
        converter.channelMap = [0]
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 10), format: format) { [weak self] buffer, _ in
            guard let self, let chunk = WakeWordListener.convert(buffer, with: converter, from: format) else { return }
            self.queue.async { self.push(chunk) }
        }
        engine.prepare()
        do { try engine.start() } catch { finish(nil); return }
        self.engine = engine
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.continuation != nil else { return }
            // Talking when time ran out: keep what was said.
            self.finish(self.speechStart.map { Array(self.samples[$0...]) })
        }
    }

    private func push(_ chunk: [Float]) {
        guard continuation != nil else { return }
        pending.append(contentsOf: chunk)
        let frame = VoiceAudio.frameLength
        while pending.count >= frame {
            let frameSamples = Array(pending.prefix(frame))
            pending.removeFirst(frame)
            samples.append(contentsOf: frameSamples)
            let time = Double(samples.count) / 16_000
            switch detector.process(level: EndpointDetector.level(of: frameSamples), at: time) {
            case .speechStarted(let at):
                speechStart = max(0, Int((at - 0.2) * 16_000))
            case .speechEnded:
                if let start = speechStart { finish(Array(samples[start...])); return }
            case nil:
                break
            }
        }
    }

    private func finish(_ result: [Float]?) {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}

/// Guides the user through the voice samples: "Optik" a few times, then a few
/// sentences, the way Siri learns a voice.
@MainActor
@Observable
final class VoiceEnrollment {
    enum State: Equatable {
        case ready
        case recording(step: Int)
        case saving
        case done
        case failed(String)
    }

    static let prompts: [String] = [
        String(localized: "Optik"),
        String(localized: "Optik"),
        String(localized: "Optik"),
        String(localized: "Optik"),
        String(localized: "Optik"),
        String(localized: "Optik, yarın saat üçte Yeliz’le kahve içeceğim."),
        String(localized: "Optik, bu ayki harcamalarımı özetler misin?"),
        String(localized: "Optik, akşam sekizde ödevi teslim etmeyi hatırlat."),
    ]

    private(set) var state: State = .ready
    private let recorder = EnrollmentRecorder()
    private var recordings: [[Float]] = []
    private var task: Task<Void, Never>?

    var currentPrompt: String? {
        if case .recording(let step) = state { return Self.prompts[step] }
        return nil
    }

    func start() {
        recordings = []
        IslandController.shared.pauseWakeWord(true)
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
        recorder.cancel()
        state = .ready
        IslandController.shared.pauseWakeWord(false)
    }

    private func run() async {
        var step = 0
        var misses = 0
        while step < Self.prompts.count {
            state = .recording(step: step)
            guard let sample = await recorder.record(), !Task.isCancelled else {
                if Task.isCancelled { return }
                misses += 1
                if misses >= 3 { fail(String(localized: "Seni duyamadım. Mikrofonu kontrol edip tekrar dener misin?")); return }
                continue
            }
            recordings.append(sample)
            step += 1
        }
        state = .saving
        do {
            _ = try await SpeakerVerifier.shared.enroll(recordings)
            state = .done
        } catch {
            fail(String(localized: "Ses profilini kaydedemedim, bir daha dener misin?"))
            return
        }
        IslandController.shared.pauseWakeWord(false)
    }

    private func fail(_ message: String) {
        state = .failed(message)
        IslandController.shared.pauseWakeWord(false)
    }
}

/// The "Sesimi tanı" sheet.
struct VoiceEnrollmentView: View {
    @State private var enrollment = VoiceEnrollment()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            switch enrollment.state {
            case .ready:
                Text("Sesini tanıyayım")
                    .font(.title2.bold())
                Text("Önce beş kez “Optik” de, sonra üç kısa cümle oku. Her birini ekranda görünce, her zamanki sesinle söyle. Kayıtlar saklanmaz, yalnızca sesinin özeti bu Mac’te kalır.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Başla") { enrollment.start() }
                    .keyboardShortcut(.defaultAction)
            case .recording(let step):
                Text("\(step + 1) / \(VoiceEnrollment.prompts.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(enrollment.currentPrompt ?? "")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 80)
                ProgressView(value: Double(step), total: Double(VoiceEnrollment.prompts.count))
                Label("Dinliyorum", systemImage: "mic.fill")
                    .foregroundStyle(.green)
            case .saving:
                ProgressView()
                Text("Sesin öğreniliyor…")
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Artık sesini tanıyorum.")
                    .font(.title3.bold())
                Button("Tamam") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .failed(let message):
                Text(message)
                    .multilineTextAlignment(.center)
                Button("Tekrar dene") { enrollment.start() }
            }
        }
        .padding(28)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if enrollment.state != .done {
                    Button("Vazgeç") {
                        enrollment.cancel()
                        dismiss()
                    }
                }
            }
        }
    }
}
