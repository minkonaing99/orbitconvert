import CoreGraphics
import Foundation
import ImageIO

// Optional Clop-style conversion of photo-like PNGs to JPEG. Only opaque PNGs whose 256 px thumbnail has at least
// 20% unique colors qualify (measured: UI and text screenshots 2-16%, photos and video captures 23-38%), and the
// JPEG is kept only when it saves at least 100 KB and 30% against the best PNG result.
extension ImageOptimizationService {
    static let convertPhotosKey = "convertPhotoPNGs"
    static let photoMinimumSaving = 100_000
    static let photoMaximumPixels = 40_000_000

    // The cheap thumbnail color count runs first; the full-image opacity check only for photo-like candidates.
    nonisolated static func isPhotoLike(_ source: CGImageSource) -> Bool {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= photoMaximumPixels / height,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256,
              ] as CFDictionary) else { return false }
        let small = (width: thumbnail.width, height: thumbnail.height)
        var pixels = [UInt8](repeating: 0, count: small.width * small.height * 4)
        guard let context = CGContext(data: &pixels, width: small.width, height: small.height, bitsPerComponent: 8,
                                      bytesPerRow: small.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
        let colors = Set(stride(from: 0, to: pixels.count, by: 4).map {
            UInt32(pixels[$0]) << 16 | UInt32(pixels[$0 + 1]) << 8 | UInt32(pixels[$0 + 2])
        })
        guard colors.count * 5 >= small.width * small.height else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil).map(isOpaque) ?? false
    }

    /// Writes a JPEG to `destination` and returns true when it is at most 30% of the original PNG and saves at least
    /// 100 KB: lossless PNG output of photos stays far above that (measured about 90%), so the slow PNG pass is skipped.
    nonisolated func jpegClearlyWins(_ source: CGImageSource, originalSize: Int64, preset: CompressionPreset,
                                     removeMetadata: Bool, to destination: URL) throws -> Bool {
        guard preset != .lossless, Self.isPhotoLike(source) else { return false }
        let jpeg = destination.deletingLastPathComponent().appendingPathComponent("early-photo.jpg")
        defer { try? FileManager.default.removeItem(at: jpeg) }
        try encode(source, to: jpeg, format: .jpeg, quality: preset == .aggressive ? 0.70 : 0.85,
                   removeMetadata: removeMetadata)
        guard let size = try? jpeg.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              Int64(size) * 10 <= originalSize * 3, originalSize - Int64(size) >= Int64(Self.photoMinimumSaving)
        else { return false }
        try FileManager.default.moveItem(at: jpeg, to: destination)
        return true
    }

    /// Replaces the PNG candidate at `temporary` with a JPEG when that is clearly smaller; returns true if it did.
    nonisolated func preferJPEG(_ source: CGImageSource, over temporary: URL, preset: CompressionPreset,
                                removeMetadata: Bool) throws -> Bool {
        guard preset != .lossless, Self.isPhotoLike(source),
              let pngSize = try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        let jpeg = temporary.deletingLastPathComponent().appendingPathComponent("photo.jpg")
        defer { try? FileManager.default.removeItem(at: jpeg) }
        try encode(source, to: jpeg, format: .jpeg, quality: preset == .aggressive ? 0.70 : 0.85,
                   removeMetadata: removeMetadata)
        guard let jpegSize = try? jpeg.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              jpegSize <= pngSize - Self.photoMinimumSaving, jpegSize * 10 <= pngSize * 7 else { return false }
        _ = try FileManager.default.replaceItemAt(temporary, withItemAt: jpeg)
        return true
    }

    // Alpha-free formats are opaque; 8-bit RGBA images must have every alpha byte at 255. Other layouts count as
    // not opaque, so they are never converted.
    nonisolated private static func isOpaque(_ image: CGImage) -> Bool {
        let info = image.alphaInfo
        if [.none, .noneSkipFirst, .noneSkipLast].contains(info) { return true }
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
        let first = [.first, .premultipliedFirst].contains(info)
        guard first || [.last, .premultipliedLast].contains(info) else { return false }
        let little = image.byteOrderInfo == .order32Little
        let offset = first != little ? 0 : 3
        for row in 0..<image.height {
            let start = row * image.bytesPerRow
            for column in 0..<image.width where bytes[start + column * 4 + offset] != 255 { return false }
        }
        return true
    }
}
