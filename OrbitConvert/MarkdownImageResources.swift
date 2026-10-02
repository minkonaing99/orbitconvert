import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Only decoded, normalized pixels cross into the document helper, never source paths.
struct MarkdownImageResources: Sendable {
    let root: URL
    let sourceDirectory: URL

    nonisolated func load(_ target: String, pixelBudget: Int = 24_000_000) throws -> (dataURI: String, pixels: Int)? {
        try Task.checkCancellation()
        guard let decoded = target.removingPercentEncoding, !decoded.hasPrefix("/"),
              URL(string: decoded)?.scheme == nil, !decoded.contains("\\"),
              !decoded.contains("?"), !decoded.contains("#") else { return nil }
        let base = root.standardizedFileURL.pathComponents
        let source = sourceDirectory.standardizedFileURL.pathComponents
        guard source.starts(with: base) else { return nil }
        let parts = Array(source.dropFirst(base.count)) + decoded.split(separator: "/").map(String.init)
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains("."), parts.count < 40 else { return nil }
        let data = try read(parts)
        guard let data, let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(imageSource) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier, UTType.heic.identifier].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8_192, height <= 8_192, width * height <= 40_000_000,
              min(width, 2_400) * min(height, 2_400) <= pixelBudget,
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(2_400, max(width, height))
              ] as CFDictionary) else { return nil }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), encoded.length <= 20_000_000 else { return nil }
        return ("data:image/png;base64," + (encoded as Data).base64EncodedString(), image.width * image.height)
    }

    nonisolated private func read(_ parts: [String]) throws -> Data? {
        var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        for (index, part) in parts.enumerated() {
            let directoryFlag = index == parts.count - 1 ? 0 : O_DIRECTORY
            let next = openat(descriptor, part, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | directoryFlag)
            guard next >= 0 else { return nil }
            close(descriptor)
            descriptor = next
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= 20_000_000 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.read(upToCount: 20_000_001)
        guard let data, data.count <= 20_000_000 else { return nil }
        return data
    }
}
