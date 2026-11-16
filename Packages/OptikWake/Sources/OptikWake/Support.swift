// Part of Optik (MIT). Works with code adapted from soniqo/speech-swift (Apache-2.0).

import CoreML
import Foundation
import os

// Small stand-ins for the parts of speech-swift's AudioCommon this module used.

enum AudioLog {
    static let modelLoading = Logger(subsystem: "OptikWake", category: "model")
    static let inference = Logger(subsystem: "OptikWake", category: "inference")
}

public enum AudioModelError: Error {
    case inferenceFailed(operation: String, reason: String)
    case invalidConfiguration(model: String, reason: String)
    case modelLoadFailed(modelId: String, reason: String)
}

enum CoreMLLoader {
    static func load(url: URL, computeUnits: MLComputeUnits, name: String) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        return try MLModel(contentsOf: url, configuration: configuration)
    }
}
