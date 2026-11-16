// Part of Optik (MIT). Works with code adapted from soniqo/speech-swift (Apache-2.0).

import Accelerate
import Foundation

// Optik: the joiner is `logits = W · tanh(encoder_out + decoder_out) + b`, with a
// 500×320 weight stored as 8-bit indices into a 256-entry fp16 table. Run as a
// Core ML model it was called ~100 times a second; here it is one matrix-vector
// product with Accelerate and no per-call allocation.

/// The joiner computed in Swift from the weights of `joiner.mlmodelc`.
public final class SwiftJoiner {
    private let weight: [Float]   // rows × columns, row-major
    private let bias: [Float]
    private let rows: Int
    private let columns: Int
    private var hidden: [Float]
    private var logits: [Float]

    /// Reads the weights; nil when the model is not the expected shape.
    init?(modelDirectory: URL) {
        let folder = modelDirectory.appendingPathComponent("joiner.mlmodelc", isDirectory: true)
        guard
            let program = try? String(contentsOf: folder.appendingPathComponent("model.mil"), encoding: .utf8),
            let blobs = try? Data(contentsOf: folder.appendingPathComponent("weights/weight.bin")),
            program.contains("tanh("), program.contains("linear("),
            program.contains("tensor<fp16, [500, 320]> output_linear_weight_to_fp16_palettized = constexpr_lut_to_dense()")
        else { return nil }
        // Blob offsets in program order: weight indices, lookup table, bias.
        let pattern = try! NSRegularExpression(pattern: #"offset = tensor<uint64, \[\]>\((\d+)\)"#)
        let offsets = pattern.matches(in: program, range: NSRange(program.startIndex..., in: program))
            .compactMap { Range($0.range(at: 1), in: program).flatMap { Int(program[$0]) } }
        guard offsets.count == 3,
              let indices = Self.blob(blobs, at: offsets[0]),
              let table = Self.blob(blobs, at: offsets[1]),
              let biasData = Self.blob(blobs, at: offsets[2]),
              indices.count == 500 * 320, table.count == 256 * 2, biasData.count == 500 * 2
        else { return nil }
        rows = 500
        columns = 320
        let lut = table.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)).map(Float.init) }
        weight = indices.map { lut[Int($0)] }
        bias = biasData.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)).map(Float.init) }
        hidden = [Float](repeating: 0, count: columns)
        logits = [Float](repeating: 0, count: rows)
    }

    func run(encoderFrame: [Float], decoderOut: [Float]) -> [Float] {
        guard encoderFrame.count == columns, decoderOut.count == columns else { return [] }
        vDSP_vadd(encoderFrame, 1, decoderOut, 1, &hidden, 1, vDSP_Length(columns))
        var count = Int32(columns)
        hidden.withUnsafeMutableBufferPointer { buffer in
            vvtanhf(buffer.baseAddress!, buffer.baseAddress!, &count)
        }
        vDSP_mmul(weight, 1, hidden, 1, &logits, 1, vDSP_Length(rows), 1, vDSP_Length(columns))
        vDSP_vadd(logits, 1, bias, 1, &logits, 1, vDSP_Length(rows))
        return logits
    }

    /// The data of one Core ML weight blob: a 64-byte header (0xDEADBEEF, data
    /// type, size, data offset) at `offset`.
    private static func blob(_ data: Data, at offset: Int) -> Data? {
        guard offset + 24 <= data.count else { return nil }
        let header = data.subdata(in: offset..<(offset + 24))
        let sentinel = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        let size = Int(header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self) })
        let start = Int(header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt64.self) })
        guard sentinel == 0xDEAD_BEEF, start + size <= data.count else { return nil }
        return data.subdata(in: start..<(start + size))
    }
}
