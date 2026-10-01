import Foundation

nonisolated enum CompressionPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case lossless, balanced, aggressive, custom

    nonisolated var id: String { rawValue }
    nonisolated var label: String {
        switch self {
        case .lossless: "Lossless"
        case .balanced: "Balanced"
        case .aggressive: "Maximum"
        case .custom: "Custom"
        }
    }
}

struct CompressionResult: Sendable {
    let originalURL: URL
    let outputURL: URL
    let originalBytes: Int64
    let outputBytes: Int64

    nonisolated var savingsBytes: Int64 { originalBytes - outputBytes }
    nonisolated var savingsPercentage: Double {
        Self.savingsPercentage(original: originalBytes, output: outputBytes)
    }

    nonisolated static func savingsPercentage(original: Int64, output: Int64) -> Double {
        guard original > 0 else { return 0 }
        return Double(original - output) / Double(original) * 100
    }
}

enum OptimizationOutcome: Sendable {
    case saved(CompressionResult)
    case noReduction(originalBytes: Int64, candidateBytes: Int64)
}

enum OptimizationError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedInput, unsupportedPreset, invalidQuality, cannotEncode, cannotWrite, protectedMetadata

    var errorDescription: String? {
        switch self {
        case .unsupportedInput: "This image format cannot be optimized on this Mac."
        case .unsupportedPreset: "This compression mode is unavailable for this file type."
        case .invalidQuality: "JPEG quality must be between 0 and 1."
        case .cannotEncode: "The optimized file could not be created or validated."
        case .cannotWrite: "The optimized file could not be saved."
        case .protectedMetadata: "This PNG contains content credentials that optimization would invalidate. Keep the original, or explicitly enable Remove metadata."
        }
    }
}
