// Measuring tool for OptikWake, not part of the app.
//   optik-wake-bench <phrase[:threshold:boost],...> file.wav...   offline, prints hits and CPU
//   optik-wake-bench <phrases> --mic <seconds>                     live microphone
// Environment: OPTIK_WAKE_MODEL (model folder), KWS_GATE=1 (sound gate), KWS_TAP (mic buffer frames),
// KWS_UNITS=ane, KWS_QOS, KWS_CHUNK, KWS_DROP, KWS_NEVER_OPEN, KWS_PREROLL_TEST.

import AVFoundation
import Foundation
import CoreML
import OptikWake

// usage: kws <keyword,keyword> file.wav...   (offline)
//        kws <keywords> --mic <seconds>     (live)
let args = CommandLine.arguments
let phrases = args[1].split(separator: ",").map { String($0) }
let specs = phrases.map { item -> KeywordSpec in
    let parts = item.split(separator: ":").map(String.init)
    return KeywordSpec(phrase: parts[0], acThreshold: parts.count > 1 ? Double(parts[1])! : 0, boost: parts.count > 2 ? Double(parts[2])! : 0)
}

func cpuSeconds() -> Double {
    var u = rusage(); getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
}

func load16k(_ path: String) throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let conv = AVAudioConverter(from: file.processingFormat, to: target)!
    let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: inBuf)
    let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1024)!
    var done = false
    var err: NSError?
    conv.convert(to: out, error: &err) { _, status in
        if done { status.pointee = .endOfStream; return nil }
        done = true; status.pointee = .haveData; return inBuf
    }
    return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
}

let t0 = Date()
let units: MLComputeUnits = ProcessInfo.processInfo.environment["KWS_UNITS"] == "ane" ? .cpuAndNeuralEngine : .cpuOnly
let modelDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OPTIK_WAKE_MODEL"] ?? (NSHomeDirectory() + "/Library/Caches/optik-wake/KWS-Zipformer-3M-CoreML-INT8"))
let detector = try WakeWordDetector.load(from: modelDir, keywords: specs, computeUnits: units)
print("loaded in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
try detector.warmUp()

if args[2] == "--mic" {
    let seconds = Double(args[3]) ?? 30
    let session = try detector.createSession()
    var liveGate = SoundGate.Configuration()
    if ProcessInfo.processInfo.environment["KWS_NEVER_OPEN"] == "1" { liveGate.minimumLevel = 10 }
    let gatedSession = try GatedWakeWordSession(detector: detector, gate: SoundGate(configuration: liveGate))
    let useGate = ProcessInfo.processInfo.environment["KWS_GATE"] == "1"
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let inFormat = input.outputFormat(forBus: 0)
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let conv = AVAudioConverter(from: inFormat, to: target)!
    conv.channelMap = [0]
    let qos: DispatchQoS = switch ProcessInfo.processInfo.environment["KWS_QOS"] {
    case "ui": .userInteractive
    case "init": .userInitiated
    case "util": .utility
    case "bg": .background
    default: .default
    }
    let queue = DispatchQueue(label: "kws", qos: qos)
    let start = Date()
    let tapSize = AVAudioFrameCount(ProcessInfo.processInfo.environment["KWS_TAP"].flatMap { Int($0) } ?? 1600)
    var reported = false
    input.installTap(onBus: 0, bufferSize: tapSize, format: inFormat) { buffer, _ in
        if !reported { reported = true; print("tap delivers \(buffer.frameLength) frames"); fflush(stdout) }
        let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / inFormat.sampleRate) + 64)!
        var given = false
        conv.convert(to: out, error: nil) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true; status.pointee = .haveData; return buffer
        }
        let samples = Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
        queue.async {
            if let hits = try? (useGate ? gatedSession.pushAudio(samples) : session.pushAudio(samples)), !hits.isEmpty {
                for h in hits { print(String(format: "%6.1f s  HIT %@", Date().timeIntervalSince(start), h.phrase)) }
                fflush(stdout)
            }
        }
    }
    try engine.start()
    let cpu0 = cpuSeconds(), wall0 = Date()
    print("listening for \(Int(seconds)) s, say: \(phrases)"); fflush(stdout)
    try await Task.sleep(for: .seconds(seconds))
    engine.stop()
    let cpu = (cpuSeconds() - cpu0) / Date().timeIntervalSince(wall0) * 100
    print(String(format: "CPU while listening: %.2f %% of one core%@", cpu, useGate ? String(format: ", model ran %.1f of %.0f s", gatedSession.processedSeconds, seconds) : ""))
} else {
    for path in args.dropFirst(2) {
        let audio0 = (0..<16_000).map { _ in Float.random(in: -0.0005...0.0005) } + (try load16k(path)) + (0..<24_000).map { _ in Float.random(in: -0.0005...0.0005) }
        let audio = Array(audio0.dropFirst(Int(ProcessInfo.processInfo.environment["KWS_DROP"] ?? "0")!))
        let c0 = cpuSeconds()
        let useGate = ProcessInfo.processInfo.environment["KWS_GATE"] == "1"
        let plain = try detector.createSession()
        if ProcessInfo.processInfo.environment["KWS_RESET_FIRST"] == "1" { try plain.reset() }
        var gateConfig = SoundGate.Configuration()
        if let v = ProcessInfo.processInfo.environment["KWS_PREROLL_TEST"] { gateConfig.minimumLevel = Double(v)!; gateConfig.floorMargin = -100; gateConfig.backgroundMargin = -100 }
        
        let gatedSession = try GatedWakeWordSession(detector: detector, gate: SoundGate(configuration: gateConfig))
        var hits: [KeywordDetection] = []
        var i = 0
        let step = Int(ProcessInfo.processInfo.environment["KWS_CHUNK"] ?? "1600")!
        while i < audio.count {   // 100 ms chunks, as live
            let end = min(i + step, audio.count)
            let chunk = Array(audio[i..<end])
            hits += try useGate ? gatedSession.pushAudio(chunk) : plain.pushAudio(chunk); i = end
        }
        if !useGate { hits += try plain.finalize() }
        let dur = Double(audio.count) / 16_000
        let cpu = (cpuSeconds() - c0) / dur * 100
        print("\((path as NSString).lastPathComponent) \(hits.map { String(format: "%.2f", Double($0.streamFrameIndex ?? 0) * 0.32 - 1) }): \(String(format: "%.1f", dur)) s, hits \(hits.map { $0.phrase }), cpu \(String(format: "%.2f", cpu)) % (realtime-equivalent)\(useGate ? String(format: ", model ran %.1f s", gatedSession.processedSeconds) : "")")
    }
}
