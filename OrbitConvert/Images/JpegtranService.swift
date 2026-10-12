import Foundation
import ImageIO
import UniformTypeIdentifiers

// Lossless JPEG optimization with the bundled mozjpeg jpegtran (BSD/IJG): optimized Huffman tables, baseline.
// Progressive output is avoided: ImageIO decodes 4:2:0 progressive JPEGs with different chroma upsampling, so
// macOS would display them differently. The result is decoded and compared with the source before use.
nonisolated struct JpegtranService: Sendable {
    static let maxBytes = 256_000_000
    static let maxPixels = 100_000_000

    init() {}

    /// Writes the rewrite to `destination` and returns true only when it is smaller and decodes to identical
    /// pixels. With `keepMetadata` false only the ICC profile is copied. Returns false (skipped) for oversized or
    /// invalid input, helper failure, a missing helper or no gain. Cancellation throws. Never overwrites.
    func optimize(_ source: URL, to destination: URL, keepMetadata: Bool, timeout: Duration = .seconds(60)) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ConversionError.cannotWriteFile }
        guard Self.withinLimits(source) else { return false }
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        let input = job.appendingPathComponent("input.jpg"), output = job.appendingPathComponent("output.jpg")
        try FileManager.default.copyItem(at: source, to: input)
        do {
            try BundledDocumentTool().run("jpegtran",
                arguments: ["-revert", "-copy", keepMetadata ? "all" : "icc", "-optimize",
                            "-outfile", "output.jpg", "input.jpg"],
                in: job, timeout: timeout)
        } catch is DocumentConversionError {
            return false
        }
        guard let before = Self.size(input), let after = Self.size(output), after < before,
              try Self.samePixels(input, output) else { return false }
        try FileManager.default.copyItem(at: output, to: destination)
        return true
    }

    private static func withinLimits(_ url: URL) -> Bool {
        guard let bytes = size(url), bytes <= maxBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else { return false }
        return width > 0 && height > 0 && width <= maxPixels / height
    }

    // Two full decodes of up to 100 MP each (ImageIO decodes lazily when the data is read); cancellation is
    // checked before each one.
    private static func samePixels(_ first: URL, _ second: URL) throws -> Bool {
        guard let a = decoded(first), let b = decoded(second),
              a.width == b.width, a.height == b.height, a.bitsPerPixel == b.bitsPerPixel,
              a.bytesPerRow == b.bytesPerRow else { return false }
        try Task.checkCancellation()
        guard let left = a.dataProvider?.data else { return false }
        try Task.checkCancellation()
        guard let right = b.dataProvider?.data else { return false }
        return (left as Data) == (right as Data)
    }

    private static func decoded(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func size(_ url: URL) -> Int? {
        try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
}
