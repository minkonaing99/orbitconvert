import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardOptimizationService: Sendable {
    nonisolated init() {}
    nonisolated func optimize(_ item: ClipboardItem, preset: CompressionPreset,
                              workingRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitConvert/Jobs"),
                              shouldSkip: @Sendable (String) -> Bool = { _ in false }) throws -> ClipboardOptimizationResult? {
        let started = Date()
        let directory = workingRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let scoped = item.fileURL?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { item.fileURL?.stopAccessingSecurityScopedResource() } }
        let bytes: Data
        if let url = item.fileURL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard url.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0, size <= 128 * 1024 * 1024 else {
                throw OptimizationError.unsupportedInput
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            bytes = try handle.read(upToCount: 128 * 1024 * 1024 + 1) ?? Data()
        } else { bytes = item.data ?? Data() }
        guard !bytes.isEmpty, bytes.count <= 128 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let identifier = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier,
               UTType.heic.identifier].contains(identifier),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 64_000_000 / height else {
            throw OptimizationError.unsupportedInput
        }
        let fingerprint = ClipboardFingerprintRegistry.fingerprint(bytes)
        guard !shouldSkip(fingerprint) else { return nil }
        let input = directory.appendingPathComponent("Clipboard.\(UTType(identifier)?.preferredFilenameExtension ?? "image")")
        try bytes.write(to: input, options: .atomic)
        guard let file = FileTypeService().inspect([input]).files.first else { throw OptimizationError.unsupportedInput }
        var optimizationFile = file
        var fallback: URL?
        if identifier == UTType.tiff.identifier {
            let converted = try ImageConversionService().convert(file, to: .png, in: directory)
            fallback = converted.outputURL
            guard let convertedFile = FileTypeService().inspect([converted.outputURL]).files.first else {
                throw OptimizationError.cannotEncode
            }
            optimizationFile = convertedFile
        }
        if preset == .lossless && [UTType.jpeg.identifier, UTType.heic.identifier].contains(identifier) { return nil }
        let candidate: URL
        switch try ImageOptimizationService().optimize(optimizationFile, in: directory, preset: preset) {
        case .saved(let result): candidate = result.outputURL
        case .noReduction:
            guard let fallback else { return nil }
            candidate = fallback
        }
        try Task.checkCancellation()
        let output = try Data(contentsOf: candidate)
        guard output.count < bytes.count else { return nil }
        guard let decoded = CGImageSourceCreateWithData(output as CFData, nil),
              CGImageSourceGetCount(decoded) == 1,
              let image = CGImageSourceCreateImageAtIndex(decoded, 0, nil),
              image.width == width, image.height == height,
              let outputType = CGImageSourceGetType(decoded) as String? else { throw OptimizationError.cannotEncode }
        return ClipboardOptimizationResult(data: output, typeIdentifier: outputType,
            originalBytes: Int64(bytes.count), width: width, height: height,
            thumbnailData: file.thumbnailData, duration: Date().timeIntervalSince(started), sourceFingerprint: fingerprint,
            outputFingerprint: ClipboardFingerprintRegistry.fingerprint(output), fileBacked: item.fileURL != nil)
    }
}
