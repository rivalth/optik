// Part of Optik (MIT). Works with code adapted from soniqo/speech-swift (Apache-2.0).

import CoreML
import Foundation

// Optik: Core ML allocates a fresh IOSurface-backed output for every prediction
// unless the caller provides one, and its pixel buffer pool then sweeps aged
// buffers on each call. With ~100 joiner calls a second that bookkeeping cost more
// than the model itself. These runners allocate every input and output once.

/// Joiner: logits for one encoder frame and one decoder output.
final class JoinerRunner {
    private let model: MLModel
    private let encoderOut: MLMultiArray
    private let decoderOut: MLMultiArray
    private let logits: MLMultiArray
    private let input: MLDictionaryFeatureProvider
    private let options = MLPredictionOptions()
    private var result: [Float]

    init(model: MLModel) throws {
        self.model = model
        encoderOut = try Self.array(for: model.modelDescription.inputDescriptionsByName["encoder_out"])
        decoderOut = try Self.array(for: model.modelDescription.inputDescriptionsByName["decoder_out"])
        logits = try Self.array(for: model.modelDescription.outputDescriptionsByName["logits"])
        input = try MLDictionaryFeatureProvider(dictionary: ["encoder_out": encoderOut, "decoder_out": decoderOut])
        options.outputBackings = ["logits": logits]
        result = [Float](repeating: 0, count: logits.count)
    }

    func run(encoderFrame: [Float], decoderOut values: [Float]) -> [Float] {
        Self.copy(encoderFrame, into: encoderOut)
        Self.copy(values, into: decoderOut)
        do {
            _ = try model.prediction(from: input, options: options)
        } catch {
            AudioLog.inference.error("kws joiner step failed: \(error)")
            return []
        }
        Self.read(logits, into: &result)
        return result
    }

    static func array(for description: MLFeatureDescription?) throws -> MLMultiArray {
        guard let constraint = description?.multiArrayConstraint else {
            throw AudioModelError.invalidConfiguration(model: "KWS-Zipformer", reason: "missing multi-array feature")
        }
        let array = try MLMultiArray(shape: constraint.shape, dataType: constraint.dataType)
        memset(array.dataPointer, 0, array.count * Self.stride(of: constraint.dataType))
        return array
    }

    static func stride(of type: MLMultiArrayDataType) -> Int {
        switch type {
        case .float16: 2
        case .double: 8
        default: 4
        }
    }

    static func copy(_ values: [Float], into array: MLMultiArray) {
        let count = min(values.count, array.count)
        values.withUnsafeBufferPointer { source in
            switch array.dataType {
            case .float16:
                let target = array.dataPointer.assumingMemoryBound(to: Float16.self)
                for i in 0..<count { target[i] = Float16(source[i]) }
            default:
                let target = array.dataPointer.assumingMemoryBound(to: Float.self)
                target.update(from: source.baseAddress!, count: count)
            }
        }
    }

    static func read(_ array: MLMultiArray, into result: inout [Float]) {
        let count = min(result.count, array.count)
        result.withUnsafeMutableBufferPointer { target in
            switch array.dataType {
            case .float16:
                let source = array.dataPointer.assumingMemoryBound(to: Float16.self)
                for i in 0..<count { target[i] = Float(source[i]) }
            default:
                let source = array.dataPointer.assumingMemoryBound(to: Float.self)
                target.baseAddress!.update(from: source, count: count)
            }
        }
    }
}

/// Decoder: the prediction network output for the last `contextSize` tokens.
/// The beam search caches its results per context, so it runs rarely.
final class DecoderRunner {
    private let model: MLModel
    private let tokens: MLMultiArray
    private let output: MLMultiArray
    private let input: MLDictionaryFeatureProvider
    private let options = MLPredictionOptions()
    private let contextSize: Int

    init(model: MLModel, contextSize: Int) throws {
        self.model = model
        self.contextSize = contextSize
        tokens = try MLMultiArray(shape: [1, contextSize as NSNumber], dataType: .int32)
        output = try JoinerRunner.array(for: model.modelDescription.outputDescriptionsByName["decoder_out"])
        input = try MLDictionaryFeatureProvider(dictionary: ["y": tokens])
        options.outputBackings = ["decoder_out": output]
    }

    func run(contextTokens: [Int]) -> [Float] {
        let target = tokens.dataPointer.assumingMemoryBound(to: Int32.self)
        for i in 0..<contextSize {
            target[i] = Int32(max(i < contextTokens.count ? contextTokens[i] : 0, 0))
        }
        do {
            _ = try model.prediction(from: input, options: options)
        } catch {
            AudioLog.inference.error("kws decoder step failed: \(error)")
            return []
        }
        var result = [Float](repeating: 0, count: output.count)
        JoinerRunner.read(output, into: &result)
        return result
    }
}

/// Encoder: one reused input window and two sets of output buffers used in turn,
/// because each call's state outputs are the next call's inputs.
final class EncoderIO {
    let input: MLMultiArray
    private var sets: [[String: MLMultiArray]] = [[:], [:]]
    private var current = 0
    private let options = [MLPredictionOptions(), MLPredictionOptions()]

    init(model: MLModel, config: KWSZipformerConfig) throws {
        input = try MLMultiArray(
            shape: [1, config.encoder.totalInputFrames as NSNumber, config.feature.numMelBins as NSNumber],
            dataType: .float32
        )
        for (name, description) in model.modelDescription.outputDescriptionsByName {
            guard let constraint = description.multiArrayConstraint, !constraint.shape.isEmpty else { continue }
            for index in 0..<2 {
                sets[index][name] = try JoinerRunner.array(for: description)
            }
        }
        options[0].outputBackings = sets[0]
        options[1].outputBackings = sets[1]
    }

    /// Options whose outputs do not alias the previous call's outputs, which are
    /// this call's state inputs.
    func nextOptions() -> MLPredictionOptions {
        current = 1 - current
        return options[current]
    }
}
