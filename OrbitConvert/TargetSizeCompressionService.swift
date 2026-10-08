import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum TargetSizeError: Error, LocalizedError {
    case invalidTarget, unreachable

    var errorDescription: String? {
        switch self {
        case .invalidTarget: "Enter a target between 1 byte and 1,000 MB."
        case .unreachable: "Cannot meet this target without going below the 1080 px short-edge minimum, or shrinking an already smaller original. Choose a larger target."
        }
    }
}

nonisolated enum TargetSizeOptions {
    static func resizeDimensions(width: Int, height: Int) -> [ResizeDimensions] {
        guard min(width, height) > 1080 else { return [] }
        let floor = 1080 / Double(min(width, height))
        var scale = 1.0
        var sizes: [ResizeDimensions] = []
        repeat {
            scale = max(floor, scale * 0.75)
            sizes.append(ResizeDimensions(width: max(1080, Int((Double(width) * scale).rounded())),
                                          height: max(1080, Int((Double(height) * scale).rounded()))))
        } while scale > floor
        return sizes
    }

    static func bytes(amount: String, megabytes: Bool) throws -> Int64 {
        guard let value = Double(amount.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw TargetSizeError.invalidTarget
        }
        let bytes = value * (megabytes ? 1_000_000 : 1_000)
        guard bytes.isFinite, bytes >= 1, bytes <= 1_000_000_000 else {
            throw TargetSizeError.invalidTarget
        }
        return Int64(bytes.rounded(.down))
    }
}

struct TargetSizeCompressionService: Sendable {
    nonisolated init() {}

    nonisolated func compress(_ file: FileItem, in directory: URL, targetBytes: Int64,
                              removeMetadata: Bool = false) throws -> FileActionReport {
        guard (1...1_000_000_000).contains(targetBytes) else { throw TargetSizeError.invalidTarget }
        guard file.url.isFileURL, file.contentTypeIdentifier == UTType.jpeg.identifier else {
            throw OptimizationError.unsupportedInput
        }
        guard directory.isFileURL else { throw ConversionError.invalidDestination }
        let sourceScoped = file.url.startAccessingSecurityScopedResource()
        defer { if sourceScoped { file.url.stopAccessingSecurityScopedResource() } }
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let displaySize = try ImageResizeService().displayDimensions(for: file)
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.bitsPerComponent <= 8,
              let originalBytes = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw OptimizationError.unsupportedInput
        }
        if originalBytes <= targetBytes {
            return FileActionReport(outputURLs: [], message: "Already within target. Original kept.", compression: nil)
        }
        let output = FileOutputService()
        let temporary = try output.makeTemporaryFile(in: directory)
        defer { output.removeTemporaryFile(temporary) }
        let match = try candidate(source, image: image, properties: properties, displaySize: displaySize,
                                  removeMetadata: removeMetadata, targetBytes: targetBytes, at: temporary)
        try Task.checkCancellation()
        let url = try output.publish(temporary, stem: file.url.deletingPathExtension().lastPathComponent + "-target-size",
                                     fileExtension: "jpg", in: directory)
        return FileActionReport(outputURLs: [url],
            message: "Saved \(url.lastPathComponent). Within target at \(match.quality)% JPEG quality; \(match.dimensions).",
            compression: CompressionResult(originalURL: file.url, outputURL: url,
                originalBytes: Int64(originalBytes), outputBytes: match.bytes))
    }

    nonisolated private func candidate(_ source: CGImageSource, image: CGImage, properties: [String: Any],
        displaySize: ResizeDimensions, removeMetadata: Bool, targetBytes: Int64,
        at url: URL) throws -> (bytes: Int64, quality: Int, dimensions: String) {
        let outputProperties = removeMetadata ? properties.filter {
            [kCGImagePropertyOrientation as String, kCGImagePropertyDPIWidth as String,
             kCGImagePropertyDPIHeight as String].contains($0.key)
        } : properties
        if let match = try findCandidate(image, properties: outputProperties, targetBytes: targetBytes, at: url) {
            try validate(url, image: image, targetBytes: targetBytes)
            return (match.bytes, match.quality, "dimensions unchanged")
        }
        for size in TargetSizeOptions.resizeDimensions(width: displaySize.width, height: displaySize.height) {
            try Task.checkCancellation()
            let match = try autoreleasepool {
                let prepared = try ImageResizeService().preparedImage(source, properties: properties,
                    dimensions: size, removeMetadata: removeMetadata)
                guard let match = try findCandidate(prepared.image, properties: prepared.properties,
                    targetBytes: targetBytes, at: url) else { return nil as (bytes: Int64, quality: Int)? }
                try validate(url, image: prepared.image, targetBytes: targetBytes)
                return match
            }
            if let match { return (match.bytes, match.quality, "resized to \(size.width) x \(size.height) px") }
        }
        throw TargetSizeError.unreachable
    }

    nonisolated private func findCandidate(_ image: CGImage, properties: [String: Any],
        targetBytes: Int64, at url: URL) throws -> (bytes: Int64, quality: Int)? {
        // shortcut: quality is sampled in 5-point steps; refine only if finer control is needed.
        for quality in stride(from: 100, through: 0, by: -5) {
            try Task.checkCancellation()
            try ImageOptimizationService().encodeResized(image, properties: properties, format: .jpeg,
                preset: .custom, jpegQuality: Double(quality) / 100, to: url)
            guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64, size > 0 else {
                throw OptimizationError.cannotEncode
            }
            if size <= targetBytes { return (Int64(size), quality) }
        }
        return nil
    }

    nonisolated private func validate(_ url: URL, image: CGImage, targetBytes: Int64) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              CGImageSourceGetCount(source) == 1, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let result = CGImageSourceCreateImageAtIndex(source, 0, nil),
              result.width == image.width, result.height == image.height,
              let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64,
              size > 0, size <= targetBytes else { throw OptimizationError.cannotEncode }
    }
}
