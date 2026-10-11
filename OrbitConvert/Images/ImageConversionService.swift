import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ConversionOptions: Sendable {
    let jpegQuality: Double
    let stripMetadata: Bool

    nonisolated init(jpegQuality: Double = 0.90, stripMetadata: Bool = false) {
        self.jpegQuality = jpegQuality
        self.stripMetadata = stripMetadata
    }
}

struct ConversionResult: Sendable {
    let sourceURL: URL
    let outputURL: URL
    let originalByteCount: Int64
    let outputByteCount: Int64
}

struct ImageConversionService: Sendable {
    private let output = FileOutputService()

    nonisolated init() {}

    nonisolated func convert(
        _ file: FileItem, to format: ConversionFormat, in directory: URL,
        options: ConversionOptions = ConversionOptions()
    ) throws -> ConversionResult {
        guard options.jpegQuality.isFinite, (0...1).contains(options.jpegQuality) else {
            throw ConversionError.invalidQuality
        }
        guard file.url.isFileURL else { throw ConversionError.unsupportedInput }
        let sourceScoped = file.url.startAccessingSecurityScopedResource()
        defer { if sourceScoped { file.url.stopAccessingSecurityScopedResource() } }
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }

        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source),
              type as String == file.contentTypeIdentifier,
              CGImageSourceGetCount(source) == 1 else {
            throw ConversionError.cannotDecode
        }
        let available = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        guard available.contains(format.typeIdentifier) else { throw ConversionError.unsupportedOutput }
        guard let originalSize = (try? file.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
            throw ConversionError.cannotDecode
        }

        let temporary = try output.makeTemporaryFile(in: directory)
        defer { output.removeTemporaryFile(temporary) }
        try encode(source, to: temporary, as: format, options: options)
        try Task.checkCancellation()
        guard let resultSource = CGImageSourceCreateWithURL(temporary as CFURL, nil),
              CGImageSourceGetType(resultSource) as String? == format.typeIdentifier,
              CGImageSourceGetCount(resultSource) == 1,
              CGImageSourceGetStatusAtIndex(resultSource, 0) == .statusComplete else {
            throw ConversionError.cannotEncode
        }
        let resultURL = try output.publish(temporary, beside: file.url, as: format, in: directory)
        let resultSize = (try? resultURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        return ConversionResult(sourceURL: file.url, outputURL: resultURL,
                                originalByteCount: Int64(originalSize), outputByteCount: Int64(resultSize))
    }

    nonisolated private func encode(
        _ source: CGImageSource, to temporary: URL, as format: ConversionFormat, options: ConversionOptions
    ) throws {
        guard CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let destination = CGImageDestinationCreateWithURL(temporary as CFURL, format.typeIdentifier as CFString, 1, nil) else {
            throw ConversionError.cannotEncode
        }
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        var properties = options.stripMetadata ? minimalProperties(from: sourceProperties) : sourceProperties
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality as String] = options.jpegQuality
        }

        if options.stripMetadata || (format == .jpeg && sourceProperties[kCGImagePropertyHasAlpha as String] as? Bool == true) {
            guard let width = sourceProperties[kCGImagePropertyPixelWidth as String] as? Int,
                  let height = sourceProperties[kCGImagePropertyPixelHeight as String] as? Int,
                  width > 0, height > 0, width <= 100_000_000 / height else {
                throw ConversionError.imageTooLarge
            }
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ConversionError.cannotDecode }
            let pixels = format == .jpeg && image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst
                && image.alphaInfo != .noneSkipLast ? try flattenedOnWhite(image) : image
            CGImageDestinationAddImage(destination, pixels, properties as CFDictionary)
        } else {
            CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.cannotEncode }
    }

    nonisolated private func minimalProperties(from source: [String: Any]) -> [String: Any] {
        let keys = [kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight]
        return keys.reduce(into: [String: Any]()) { result, key in
            if let value = source[key as String] { result[key as String] = value }
        }
    }

    nonisolated private func flattenedOnWhite(_ image: CGImage) throws -> CGImage {
        let colorSpace = image.colorSpace?.model == .rgb ? image.colorSpace : nil
        let rgb = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: rgb,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ConversionError.cannotEncode
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = context.makeImage() else { throw ConversionError.cannotEncode }
        return result
    }
}
