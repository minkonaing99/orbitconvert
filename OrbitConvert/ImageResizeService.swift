import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ResizePreset: String, CaseIterable, Identifiable, Sendable {
    case quarter, half, threeQuarters, edge1080, edge1920, custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .quarter: "25%"
        case .half: "50%"
        case .threeQuarters: "75%"
        case .edge1080: "1080 px"
        case .edge1920: "1920 px"
        case .custom: "Custom"
        }
    }
}

nonisolated struct ResizeDimensions: Equatable, Sendable {
    let width: Int
    let height: Int
}

nonisolated struct ResizeOptions: Sendable {
    var preset: ResizePreset = .half
    var width: Int = 1920
    var height: Int = 1080

    func dimensions(width sourceWidth: Int, height sourceHeight: Int) throws -> ResizeDimensions {
        guard sourceWidth > 0, sourceHeight > 0, sourceWidth <= 100_000,
              sourceHeight <= 100_000, sourceWidth <= 100_000_000 / sourceHeight else {
            throw ConversionError.imageTooLarge
        }
        let scale: Double
        switch preset {
        case .quarter: scale = 0.25
        case .half: scale = 0.5
        case .threeQuarters: scale = 0.75
        case .edge1080: scale = min(1, 1080 / Double(max(sourceWidth, sourceHeight)))
        case .edge1920: scale = min(1, 1920 / Double(max(sourceWidth, sourceHeight)))
        case .custom:
            guard width > 0, height > 0, width <= 100_000, height <= 100_000 else {
                throw ResizeError.invalidDimensions
            }
            scale = min(1, min(Double(width) / Double(sourceWidth), Double(height) / Double(sourceHeight)))
        }
        return ResizeDimensions(width: max(1, Int((Double(sourceWidth) * scale).rounded())),
                                height: max(1, Int((Double(sourceHeight) * scale).rounded())))
    }
}

nonisolated enum ResizeError: Error, LocalizedError, Sendable {
    case invalidDimensions
    var errorDescription: String? { "Enter dimensions between 1 and 100,000 pixels." }
}

struct ImageResizeService: Sendable {
    nonisolated init() {}

    nonisolated static func supports(_ file: FileItem) -> Bool {
        guard let format = ConversionFormat.sourceFormat(for: file.contentTypeIdentifier),
              [.jpeg, .png, .heic].contains(format) else { return false }
        return (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(format.typeIdentifier)
    }

    nonisolated func displayDimensions(for file: FileItem) throws -> ResizeDimensions {
        guard file.url.isFileURL, Self.supports(file) else { throw OptimizationError.unsupportedInput }
        let scoped = file.url.startAccessingSecurityScopedResource()
        defer { if scoped { file.url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == file.contentTypeIdentifier,
              CGImageSourceGetCount(source) == 1, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else {
            throw OptimizationError.unsupportedInput
        }
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        guard (1...8).contains(orientation) else { throw OptimizationError.unsupportedInput }
        guard (properties[kCGImagePropertyDepth as String] as? Int ?? 8) <= 8,
              CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) == nil else {
            throw OptimizationError.unsupportedInput
        }
        return try ResizeOptions(preset: .custom, width: 100_000, height: 100_000)
            .dimensions(width: orientation >= 5 ? height : width, height: orientation >= 5 ? width : height)
    }

    nonisolated func resize(_ file: FileItem, in directory: URL, options: ResizeOptions,
                            preset: CompressionPreset = .balanced, jpegQuality: Double? = nil,
                            removeMetadata: Bool = false) throws -> OptimizationOutcome {
        guard file.url.isFileURL, directory.isFileURL, Self.supports(file),
              let format = ConversionFormat.sourceFormat(for: file.contentTypeIdentifier) else {
            throw OptimizationError.unsupportedInput
        }
        let sourceScoped = file.url.startAccessingSecurityScopedResource()
        defer { if sourceScoped { file.url.stopAccessingSecurityScopedResource() } }
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == file.contentTypeIdentifier,
              CGImageSourceGetCount(source) == 1, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              let originalBytes = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw OptimizationError.unsupportedInput
        }
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        guard (1...8).contains(orientation) else { throw OptimizationError.unsupportedInput }
        guard (properties[kCGImagePropertyDepth as String] as? Int ?? 8) <= 8,
              CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) == nil else {
            throw OptimizationError.unsupportedInput
        }
        let dimensions = try options.dimensions(width: orientation >= 5 ? height : width,
                                                height: orientation >= 5 ? width : height)
        if format == .png, !removeMetadata { try OxipngService().validateRewrite(of: file.url) }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitConvert/Jobs/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: work) }
        let resized = work.appendingPathComponent("resized.\(format.fileExtension)")
        try createResized(source, properties: properties, dimensions: dimensions,
                          format: format, removeMetadata: removeMetadata, preset: preset,
                          jpegQuality: jpegQuality, destination: resized)
        let candidate = try optimizedCandidate(resized, file: file, format: format,
                                               dimensions: dimensions, preset: preset)
        return try publishResult(candidate, file: file, in: directory, format: format,
                                 dimensions: dimensions, originalBytes: Int64(originalBytes))
    }

    nonisolated private func optimizedCandidate(_ resized: URL, file: FileItem,
        format: ConversionFormat, dimensions: ResizeDimensions, preset: CompressionPreset) throws -> URL {
        guard format == .png else { return resized }
        let intermediate = FileItem(url: resized, fileName: resized.lastPathComponent,
            fileExtension: format.fileExtension, contentTypeIdentifier: format.typeIdentifier,
            contentTypeName: file.contentTypeName, fileSize: 0, creationDate: nil,
            pixelWidth: dimensions.width, pixelHeight: dimensions.height,
            pageCount: nil, thumbnailData: Data(), supportedConversions: [])
        switch try ImageOptimizationService().optimize(intermediate,
            in: resized.deletingLastPathComponent(), preset: preset) {
        case .saved(let result): return result.outputURL
        case .noReduction: return resized
        }
    }

    nonisolated private func publishResult(_ candidate: URL, file: FileItem, in directory: URL,
        format: ConversionFormat, dimensions: ResizeDimensions, originalBytes: Int64) throws -> OptimizationOutcome {
        try Task.checkCancellation()
        let candidateBytes = try validatedSize(candidate, format: format, dimensions: dimensions)
        guard candidateBytes < originalBytes else {
            return .noReduction(originalBytes: originalBytes, candidateBytes: candidateBytes)
        }
        let output = FileOutputService()
        let staged = try output.makeTemporaryFile(in: directory)
        defer { output.removeTemporaryFile(staged) }
        try FileManager.default.copyItem(at: candidate, to: staged)
        try Task.checkCancellation()
        let result = try output.publish(staged,
            stem: file.url.deletingPathExtension().lastPathComponent + "-resized",
            fileExtension: format.fileExtension, in: directory)
        return .saved(CompressionResult(originalURL: file.url, outputURL: result,
                                       originalBytes: originalBytes, outputBytes: candidateBytes))
    }

    nonisolated private func createResized(_ source: CGImageSource, properties: [String: Any],
        dimensions: ResizeDimensions, format: ConversionFormat, removeMetadata: Bool,
        preset: CompressionPreset, jpegQuality: Double?, destination url: URL) throws {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: max(dimensions.width, dimensions.height)] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              thumbnail.bitsPerComponent <= 8 else { throw OptimizationError.unsupportedInput }
        let image = try exactImage(thumbnail, dimensions: dimensions)
        let outputProperties = normalized(properties, dimensions: dimensions, removeMetadata: removeMetadata)
        try ImageOptimizationService().encodeResized(image, properties: outputProperties,
            format: format, preset: preset, jpegQuality: jpegQuality, to: url)
    }

    nonisolated private func exactImage(_ image: CGImage, dimensions: ResizeDimensions) throws -> CGImage {
        if image.width == dimensions.width, image.height == dimensions.height { return image }
        guard let space = image.colorSpace, space.model == .rgb,
              let context = CGContext(data: nil, width: dimensions.width, height: dimensions.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw OptimizationError.cannotEncode }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height))
        guard let result = context.makeImage() else { throw OptimizationError.cannotEncode }
        return result
    }

    nonisolated private func normalized(_ properties: [String: Any], dimensions: ResizeDimensions,
                                        removeMetadata: Bool) -> [String: Any] {
        var result = removeMetadata ? [:] : properties
        result[kCGImagePropertyPixelWidth as String] = dimensions.width
        result[kCGImagePropertyPixelHeight as String] = dimensions.height
        result[kCGImagePropertyOrientation as String] = 1
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] { result[key as String] = properties[key as String] }
        if !removeMetadata {
            var exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
            exif[kCGImagePropertyExifPixelXDimension as String] = dimensions.width
            exif[kCGImagePropertyExifPixelYDimension as String] = dimensions.height
            result[kCGImagePropertyExifDictionary as String] = exif
            var tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            result[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        result.removeValue(forKey: "ThumbnailImages")
        result.removeValue(forKey: "Thumbnail")
        return result
    }

    nonisolated private func validatedSize(_ url: URL, format: ConversionFormat,
                                          dimensions: ResizeDimensions) throws -> Int64 {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == format.typeIdentifier,
              CGImageSourceGetCount(source) == 1, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == dimensions.width, image.height == dimensions.height,
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw OptimizationError.cannotEncode
        }
        return Int64(size)
    }
}
