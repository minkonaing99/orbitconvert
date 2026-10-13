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
                              removeMetadata: Bool = false,
                              palette: PaletteLevel = .off) throws -> OptimizationOutcome {
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
            try encodePNG(file.url, source: source, to: temporary, preset: preset,
                          removeMetadata: removeMetadata, palette: palette)
        } else if format == .jpeg, let quality {
            if let estimate = try encodeJPEG(file.url, source: source, to: temporary, quality: quality,
                                             removeMetadata: removeMetadata) {
                return .noReduction(originalBytes: Int64(originalSize), candidateBytes: Int64(originalSize),
                                    estimatedJPEGQuality: estimate)
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

    nonisolated private func encodePNG(_ url: URL, source: CGImageSource, to temporary: URL,
                                       preset: CompressionPreset, removeMetadata: Bool, palette: PaletteLevel) throws {
        if palette != .off, try paletteCandidate(url, to: temporary, preset: preset, level: palette,
                                                 removeMetadata: removeMetadata) { return }
        if removeMetadata {
            let stripped = temporary.deletingLastPathComponent().appendingPathComponent("stripped.png")
            try encode(source, to: stripped, format: .png, quality: nil, removeMetadata: true)
            try OxipngService().optimize(source: stripped, destination: temporary, preset: preset)
        } else {
            try OxipngService().optimize(source: url, destination: temporary, preset: preset)
        }
    }

    // Returns the source quality estimate when the JPEG is already compressed and no lossless rewrite helps.
    // Otherwise writes the smallest of: ImageIO re-encode, its lossless rewrite, the source's lossless rewrite.
    // Lossless metadata removal drops the EXIF orientation, so rotated photos are re-encoded instead.
    nonisolated private func encodeJPEG(_ url: URL, source: CGImageSource, to temporary: URL,
                                        quality: Double, removeMetadata: Bool) throws -> Int? {
        let jpegtran = JpegtranService()
        let lossless = !removeMetadata || Self.isUpright(source)
        if lossless, let estimate = JPEGQualityEstimator.estimate(contentsOf: url),
           let target = JPEGQualityEstimator.imageIOEquivalent(quality), estimate <= target {
            return try jpegtran.optimize(url, to: temporary, keepMetadata: !removeMetadata) ? nil : estimate
        }
        let work = temporary.deletingLastPathComponent()
        let reencoded = work.appendingPathComponent("reencoded.jpg")
        let rewritten = work.appendingPathComponent("reencoded-lossless.jpg")
        let fromSource = work.appendingPathComponent("source-lossless.jpg")
        try encode(source, to: reencoded, format: .jpeg, quality: quality, removeMetadata: removeMetadata)
        let rewrote = try jpegtran.optimize(reencoded, to: rewritten, keepMetadata: true)
        let sourceRewrote = try lossless && jpegtran.optimize(url, to: fromSource, keepMetadata: !removeMetadata)
        let candidates = [reencoded] + (rewrote ? [rewritten] : []) + (sourceRewrote ? [fromSource] : [])
        let sizes = candidates.map { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max }
        let best = candidates[sizes.firstIndex(of: sizes.min() ?? .max) ?? 0]
        try FileManager.default.moveItem(at: best, to: temporary)
        return nil
    }

    nonisolated private static func isUpright(_ source: CGImageSource) -> Bool {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        return (properties?[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1
    }

    // Palette output drops metadata, so content credentials still require an explicit Remove metadata choice.
    // Returns false when pngquant skips the file, so the lossless path runs instead.
    nonisolated private func paletteCandidate(_ url: URL, to temporary: URL, preset: CompressionPreset,
                                              level: PaletteLevel, removeMetadata: Bool) throws -> Bool {
        if !removeMetadata { try OxipngService().validateRewrite(of: url) }
        let quantized = temporary.deletingLastPathComponent().appendingPathComponent("palette.png")
        defer { try? FileManager.default.removeItem(at: quantized) }
        guard try PngquantService().quantize(url, to: quantized, level: level) else { return false }
        try OxipngService().optimize(source: quantized, destination: temporary, preset: preset)
        return true
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
