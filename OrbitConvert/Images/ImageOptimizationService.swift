import Foundation
import ImageIO

struct ImageOptimizationService: Sendable {
    private let output = FileOutputService()

    nonisolated init() {}

    nonisolated func encodeResized(_ image: CGImage, properties: [String: Any], format: ConversionFormat,
                                   preset: CompressionPreset, jpegQuality: Double?, to url: URL) throws {
        let quality = try resolvedQuality(for: format, preset: preset, custom: jpegQuality)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
            format.typeIdentifier as CFString, 1, nil) else { throw OptimizationError.cannotEncode }
        var resolvedProperties = properties
        if let quality { resolvedProperties[kCGImageDestinationLossyCompressionQuality as String] = quality }
        CGImageDestinationAddImage(destination, image, resolvedProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw OptimizationError.cannotEncode }
    }

    nonisolated func optimize(_ file: FileItem, in directory: URL,
                              preset: CompressionPreset = .balanced,
                              jpegQuality: Double? = nil,
                              removeMetadata: Bool = false) throws -> OptimizationOutcome {
        guard let format = ConversionFormat.sourceFormat(for: file.contentTypeIdentifier),
              [.jpeg, .png, .heic].contains(format) else { throw OptimizationError.unsupportedInput }
        guard Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(format.typeIdentifier) else {
            throw OptimizationError.unsupportedInput
        }
        let quality = try resolvedQuality(for: format, preset: preset, custom: jpegQuality)
        let sourceScoped = file.url.startAccessingSecurityScopedResource()
        defer { if sourceScoped { file.url.stopAccessingSecurityScopedResource() } }
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == file.contentTypeIdentifier,
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let originalSize = try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw OptimizationError.unsupportedInput
        }
        let temporary = try output.makeTemporaryFile(in: directory)
        defer { output.removeTemporaryFile(temporary) }
        if format == .png {
            if removeMetadata {
                let stripped = temporary.deletingLastPathComponent().appendingPathComponent("stripped.png")
                try encode(source, to: stripped, format: format, quality: nil, removeMetadata: true)
                try OxipngService().optimize(source: stripped, destination: temporary, preset: preset)
            } else {
                try OxipngService().optimize(source: file.url, destination: temporary, preset: preset)
            }
        } else {
            try encode(source, to: temporary, format: format, quality: quality, removeMetadata: removeMetadata)
        }
        try Task.checkCancellation()
        guard let candidate = CGImageSourceCreateWithURL(temporary as CFURL, nil),
              CGImageSourceGetType(candidate) as String? == format.typeIdentifier,
              CGImageSourceGetCount(candidate) == 1,
              CGImageSourceGetStatusAtIndex(candidate, 0) == .statusComplete,
              let originalImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let candidateImage = CGImageSourceCreateImageAtIndex(candidate, 0, nil),
              originalImage.width == candidateImage.width, originalImage.height == candidateImage.height,
              let candidateSize = try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw OptimizationError.cannotEncode
        }
        guard candidateSize < originalSize else {
            return .noReduction(originalBytes: Int64(originalSize), candidateBytes: Int64(candidateSize))
        }
        let stem = file.url.deletingPathExtension().lastPathComponent + "-optimized"
        let url = try output.publish(temporary, stem: stem, fileExtension: format.fileExtension, in: directory)
        return .saved(CompressionResult(originalURL: file.url, outputURL: url,
                                        originalBytes: Int64(originalSize), outputBytes: Int64(candidateSize)))
    }

    nonisolated private func resolvedQuality(for format: ConversionFormat,
                                             preset: CompressionPreset, custom: Double?) throws -> Double? {
        guard format == .jpeg || format == .heic else {
            if preset == .custom { throw OptimizationError.unsupportedPreset }
            return nil
        }
        switch preset {
        case .lossless: throw OptimizationError.unsupportedPreset
        case .balanced: return 0.85
        case .aggressive: return 0.70
        case .custom:
            guard let custom, custom.isFinite, (0...1).contains(custom) else { throw OptimizationError.invalidQuality }
            return custom
        }
    }

    nonisolated private func encode(_ source: CGImageSource, to url: URL,
                                    format: ConversionFormat, quality: Double?,
                                    removeMetadata: Bool) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                format.typeIdentifier as CFString, 1, nil) else {
            throw OptimizationError.cannotEncode
        }
        var properties: [String: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality as String] = quality }
        if removeMetadata {
            let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
            guard let width = sourceProperties[kCGImagePropertyPixelWidth as String] as? Int,
                  let height = sourceProperties[kCGImagePropertyPixelHeight as String] as? Int,
                  width > 0, height > 0, width <= 100_000_000 / height,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw OptimizationError.cannotEncode
            }
            for key in [kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
                properties[key as String] = sourceProperties[key as String]
            }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        } else {
            CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw OptimizationError.cannotEncode }
    }
}
