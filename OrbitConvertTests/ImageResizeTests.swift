import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class ImageResizeTests: XCTestCase {
    func testPresetsMaintainAspectRatioWithoutEnlarging() throws {
        XCTAssertEqual(try ResizeOptions().dimensions(width: 2000, height: 1000), ResizeDimensions(width: 1000, height: 500))
        XCTAssertEqual(try ResizeOptions(preset: .edge1080).dimensions(width: 2000, height: 1000), ResizeDimensions(width: 1080, height: 540))
        XCTAssertEqual(try ResizeOptions(preset: .edge1920).dimensions(width: 640, height: 480), ResizeDimensions(width: 640, height: 480))
        XCTAssertEqual(try ResizeOptions(preset: .custom, width: 300, height: 300).dimensions(width: 800, height: 400), ResizeDimensions(width: 300, height: 150))
    }

    func testInvalidDimensionsRejected() {
        XCTAssertThrowsError(try ResizeOptions(preset: .custom, width: 0, height: 100).dimensions(width: 100, height: 100))
        XCTAssertThrowsError(try ResizeOptions().dimensions(width: Int.max, height: Int.max))
        XCTAssertEqual(try? ResizeOptions(preset: .quarter).dimensions(width: 400, height: 240), ResizeDimensions(width: 100, height: 60))
        XCTAssertEqual(try? ResizeOptions(preset: .threeQuarters).dimensions(width: 400, height: 240), ResizeDimensions(width: 300, height: 180))
    }

    func testAllOrientationsNormalizeAndPreserveOriginal() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for orientation in 1...8 {
            let source = folder.appendingPathComponent("orientation-\(orientation).jpg")
            try makeImage(at: source, type: .jpeg, orientation: orientation)
            let before = try Data(contentsOf: source)
            let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
            let displayed = try ImageResizeService().displayDimensions(for: item)
            XCTAssertEqual(displayed, orientation >= 5 ? ResizeDimensions(width: 240, height: 400) : ResizeDimensions(width: 400, height: 240))
            let outcome = try ImageResizeService().resize(item, in: folder, options: ResizeOptions())
            guard case .saved(let result) = outcome else { return XCTFail("Expected smaller resized JPEG") }
            let output = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(output, 0, nil))
            XCTAssertEqual(image.width, displayed.width / 2)
            XCTAssertEqual(image.height, displayed.height / 2)
            let originalImageSource = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
            let originalImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(originalImageSource, 0, nil))
            let rawCorners = try cornerColors(originalImage)
            let mapping = [[0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
                           [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]][orientation - 1]
            let normalizedCorners = try cornerColors(image)
            for corner in 0..<4 {
                for channel in 0..<3 {
                    XCTAssertEqual(Double(normalizedCorners[corner][channel]),
                                   Double(rawCorners[mapping[corner]][channel]), accuracy: 30,
                                   "Orientation \(orientation), corner \(corner)")
                }
            }
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [String: Any])
            XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int ?? 1, 1)
            XCTAssertEqual(try Data(contentsOf: source), before)
            XCTAssertEqual(result.originalBytes, Int64(before.count))
        }
    }

    func testTransparentPNGMetadataAndFilenameCollision() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("alpha.png")
        try makeImage(at: source, type: .png)
        let collision = folder.appendingPathComponent("alpha-resized.png")
        let sentinel = Data("existing output".utf8)
        try sentinel.write(to: collision)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        let outcome = try ImageResizeService().resize(item, in: folder, options: ResizeOptions())
        guard case .saved(let result) = outcome else { return XCTFail("Expected smaller resized PNG") }
        XCTAssertEqual(result.outputURL.lastPathComponent, "alpha-resized-1.png")
        XCTAssertEqual(try Data(contentsOf: collision), sentinel)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 120)
        XCTAssertFalse([.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo))
        let pixelContext = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        pixelContext.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = try XCTUnwrap(pixelContext.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(pixel[3], 100)
        XCTAssertLessThan(pixel[3], 160)
        XCTAssertNotNil(image.colorSpace)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyDPIWidth as String] as? Double ?? 0, 144, accuracy: 1)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".orbitconvert-") })
    }

    func testCorruptedInputAndUnsupportedFormatDoNotCreateOutput() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.jpg")
        try makeImage(at: source, type: .jpeg)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        let corrupt = Data("corrupted".utf8)
        try corrupt.write(to: source)
        XCTAssertThrowsError(try ImageResizeService().resize(item, in: folder, options: ResizeOptions()))
        XCTAssertEqual(try Data(contentsOf: source), corrupt)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["photo.jpg"])
        let tiff = folder.appendingPathComponent("image.tiff")
        try makeImage(at: tiff, type: .tiff)
        let unsupported = try XCTUnwrap(FileTypeService().inspect([tiff]).files.first)
        XCTAssertFalse(ImageResizeService.supports(unsupported))
        XCTAssertThrowsError(try ImageResizeService().resize(unsupported, in: folder, options: ResizeOptions()))
    }

    func testHEICUsesInstalledEncoder() throws {
        guard (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(UTType.heic.identifier) else {
            throw XCTSkip("HEIC encoder not available")
        }
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.heic")
        try makeImage(at: source, type: .heic)
        let original = try Data(contentsOf: source)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        let result = try ImageResizeService().resize(item, in: folder, options: ResizeOptions())
        guard case .saved(let saved) = result else { return XCTFail("Expected smaller resized HEIC") }
        XCTAssertEqual(saved.outputURL.pathExtension, "heic")
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    @MainActor
    func testCancelledJobPreservesOriginal() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.jpg")
        try makeImage(at: source, type: .jpeg)
        let original = try Data(contentsOf: source)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        let task = Task.detached {
            try? await Task.sleep(for: .milliseconds(20))
            return try ImageResizeService().resize(item, in: folder, options: ResizeOptions())
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["photo.jpg"])
    }

    func testMetadataRemovalIsExplicit() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.jpg")
        try makeImage(at: source, type: .jpeg)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        for remove in [false, true] {
            let outcome = try ImageResizeService().resize(item, in: folder, options: ResizeOptions(), removeMetadata: remove)
            guard case .saved(let result) = outcome else { return XCTFail("Expected resized result") }
            let output = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [String: Any])
            let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
            XCTAssertEqual(exif?[kCGImagePropertyExifUserComment as String] as? String, remove ? nil : "Keep my camera note")
            XCTAssertEqual(exif?[kCGImagePropertyExifPixelXDimension as String] as? Int ?? 200, 200)
        }
    }

    func testLargerCandidateIsNotPublished() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("small.jpg")
        try makeImage(at: source, type: .jpeg, quality: 0.01)
        let original = try Data(contentsOf: source)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        let outcome = try ImageResizeService().resize(item, in: folder, options: ResizeOptions(preset: .edge1920))
        guard case .noReduction(let bytes, let candidate) = outcome else { return XCTFail("Larger candidate must be skipped") }
        XCTAssertEqual(bytes, Int64(original.count))
        XCTAssertGreaterThanOrEqual(candidate, bytes)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["small.jpg"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cornerColors(_ image: CGImage) throws -> [[UInt8]] {
        let points = [(3, 3), (image.width - 4, 3), (3, image.height - 4),
                      (image.width - 4, image.height - 4)]
        return try points.map { x, y in
            let cropped = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            return [pixels[0], pixels[1], pixels[2]]
        }
    }

    private func makeImage(at url: URL, type: UTType, orientation: Int = 1, quality: Double = 1) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 240, bitsPerComponent: 8,
            bytesPerRow: 0, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for y in 0..<240 {
            for x in 0..<400 {
                context.setFillColor(CGColor(red: CGFloat((x * 47 + y * 13) % 255) / 255,
                    green: CGFloat((x * 19 + y * 31) % 255) / 255, blue: 0.4, alpha: type == .png ? 0.5 : 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        if type != .png {
            for (rectangle, color) in [
                (CGRect(x: 0, y: 0, width: 24, height: 24), CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
                (CGRect(x: 376, y: 0, width: 24, height: 24), CGColor(red: 0, green: 1, blue: 0, alpha: 1)),
                (CGRect(x: 0, y: 216, width: 24, height: 24), CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
                (CGRect(x: 376, y: 216, width: 24, height: 24), CGColor(red: 1, green: 1, blue: 0, alpha: 1))
            ] {
                context.setFillColor(color)
                context.fill(rectangle)
            }
        }
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: orientation, kCGImagePropertyDPIWidth: 144,
            kCGImagePropertyDPIHeight: 144,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Keep my camera note"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
