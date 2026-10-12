import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class JpegtranTests: XCTestCase {
    func testLosslessRewriteIsSmallerBaselineAndPixelIdentical() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeJPEG(to: folder.appendingPathComponent("photo.jpg"))
        let output = folder.appendingPathComponent("out.jpg")

        XCTAssertTrue(try JpegtranService().optimize(source, to: output, keepMetadata: true))

        XCTAssertLessThan(try size(output), try size(source))
        XCTAssertEqual(try pixels(output), try pixels(source))
        let jfif = try properties(output)[kCGImagePropertyJFIFDictionary as String] as? [String: Any]
        XCTAssertNotEqual(jfif?[kCGImagePropertyJFIFIsProgressive as String] as? Bool, true)
    }

    func testMetadataKeptOrRemovedButColorProfileStays() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeJPEG(to: folder.appendingPathComponent("photo.jpg"), make: "OrbitTestCam")
        let kept = folder.appendingPathComponent("kept.jpg"), stripped = folder.appendingPathComponent("stripped.jpg")

        XCTAssertTrue(try JpegtranService().optimize(source, to: kept, keepMetadata: true))
        XCTAssertTrue(try JpegtranService().optimize(source, to: stripped, keepMetadata: false))

        XCTAssertEqual(try make(kept), "OrbitTestCam")
        XCTAssertNil(try make(stripped))
        XCTAssertNotNil(try properties(stripped)[kCGImagePropertyProfileName as String])
        XCTAssertEqual(try pixels(stripped), try pixels(source))
    }

    func testRewriteOfOptimizedFileIsSkipped() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeJPEG(to: folder.appendingPathComponent("photo.jpg"))
        let once = folder.appendingPathComponent("once.jpg"), twice = folder.appendingPathComponent("twice.jpg")
        XCTAssertTrue(try JpegtranService().optimize(source, to: once, keepMetadata: true))

        XCTAssertFalse(try JpegtranService().optimize(once, to: twice, keepMetadata: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: twice.path))
    }

    func testInvalidInputIsSkippedAndExistingDestinationRejected() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeJPEG(to: folder.appendingPathComponent("photo.jpg"))
        let truncated = folder.appendingPathComponent("truncated.jpg")
        try Data(contentsOf: source).prefix(600).write(to: truncated)
        let text = folder.appendingPathComponent("note.jpg")
        try Data("not a jpeg".utf8).write(to: text)
        let output = folder.appendingPathComponent("out.jpg")

        XCTAssertFalse(try JpegtranService().optimize(truncated, to: output, keepMetadata: true))
        XCTAssertFalse(try JpegtranService().optimize(text, to: output, keepMetadata: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertThrowsError(try JpegtranService().optimize(source, to: source, keepMetadata: true))
    }

    func testAlreadyCompressedJPEGGetsOnlyLosslessRewrite() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeJPEG(to: folder.appendingPathComponent("small.jpg"), quality: 0.5)

        guard case .saved(let result) = try optimize(source, in: folder) else {
            return XCTFail("Lossless rewrite expected")
        }
        XCTAssertEqual(try pixels(result.outputURL), try pixels(source))
    }

    func testAlreadyOptimizedJPEGReportsEstimateWithoutOutput() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let raw = try writeJPEG(to: folder.appendingPathComponent("raw.jpg"), quality: 0.5)
        let source = folder.appendingPathComponent("small.jpg")
        XCTAssertTrue(try JpegtranService().optimize(raw, to: source, keepMetadata: true))
        let bytes = Int64(try size(source))

        guard case .noReduction(let original, let candidate, let estimate) = try optimize(source, in: folder) else {
            return XCTFail("Already-optimized JPEG must be kept")
        }
        XCTAssertEqual([original, candidate], [bytes, bytes])
        XCTAssertEqual(estimate, JPEGQualityEstimator.imageIOEquivalent(0.5))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["raw.jpg", "small.jpg"])
    }

    func testRemoveMetadataStripsUprightJPEGLosslessly() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeJPEG(to: folder.appendingPathComponent("small.jpg"), make: "OrbitTestCam", quality: 0.5)

        guard case .saved(let result) = try optimize(source, in: folder, removeMetadata: true) else {
            return XCTFail("Lossless strip expected")
        }
        XCTAssertNil(try make(result.outputURL))
        XCTAssertEqual(try pixels(result.outputURL), try pixels(source))
    }

    func testRemoveMetadataOnRotatedJPEGKeepsOrientationThroughReencode() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeJPEG(to: folder.appendingPathComponent("small.jpg"), make: "OrbitTestCam",
                                   quality: 0.5, orientation: 6)

        switch try optimize(source, in: folder, removeMetadata: true) {
        case .saved(let result):
            XCTAssertNil(try make(result.outputURL))
            XCTAssertEqual(try properties(result.outputURL)[kCGImagePropertyOrientation as String] as? Int, 6)
        case .noReduction(_, _, let estimate):
            XCTAssertNil(estimate)
        }
    }

    func testReencodedJPEGIsAlsoLosslesslyOptimized() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeJPEG(to: folder.appendingPathComponent("photo.jpg"), quality: 1.0)

        let plain = folder.appendingPathComponent("plain.jpg")
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(plain as CFURL,
            UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImageFromSource(destination, image, 0,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        guard case .saved(let result) = try optimize(source, in: folder) else { return XCTFail("Expected reduction") }
        XCTAssertLessThan(result.outputBytes, Int64(try size(plain)))
        try FileManager.default.removeItem(at: plain)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)),
                       ["photo.jpg", "photo-optimized.jpg"])
    }

    private func optimize(_ url: URL, in folder: URL, removeMetadata: Bool = false) throws -> OptimizationOutcome {
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)
        return try ImageOptimizationService().optimize(file, in: folder, preset: .balanced, removeMetadata: removeMetadata)
    }

    // Noise-like content at quality 0.9 leaves Huffman and progressive savings for jpegtran.
    func writeJPEG(to url: URL, make: String? = nil, quality: Double = 0.9,
                   orientation: Int? = nil) throws -> URL {
        let width = 480, height = 320
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let wave = (sin(Double(x) / 23) + cos(Double(y) / 17) + 2) / 4
                context.setFillColor(red: wave, green: Double((x * 7 + y * 3) % 255) / 255,
                                     blue: 1 - wave, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        var options: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: quality]
        if let make { options[kCGImagePropertyTIFFDictionary as String] = [kCGImagePropertyTIFFMake as String: make] }
        if let orientation { options[kCGImagePropertyOrientation as String] = orientation }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), options as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func pixels(_ url: URL) throws -> Data? {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)).dataProvider?.data as Data?
    }

    func make(_ url: URL) throws -> String? {
        let tiff = try properties(url)[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        return tiff?[kCGImagePropertyTIFFMake as String] as? String
    }

    func properties(_ url: URL) throws -> [String: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
    }

    func size(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
