import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class ImageOptimizationServiceTests: XCTestCase {
    func testSavingsMathHandlesZeroAndGrowth() {
        XCTAssertEqual(CompressionResult.savingsPercentage(original: 0, output: 0), 0)
        XCTAssertEqual(CompressionResult.savingsPercentage(original: 1_000, output: 250), 75)
        XCTAssertEqual(CompressionResult.savingsPercentage(original: 1_000, output: 1_250), -25)
    }

    func testJPEGOptimizationKeepsOriginalAndPublishesOnlySmallerResult() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.jpg")
        try makeImage(at: source, type: .jpeg, quality: 1.0)
        let before = try Data(contentsOf: source)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)

        let outcome = try ImageOptimizationService().optimize(item, in: folder, preset: .aggressive)

        XCTAssertEqual(try Data(contentsOf: source), before)
        if case .saved(let result) = outcome {
            XCTAssertLessThan(result.outputBytes, result.originalBytes)
            let image = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(image) as String?, UTType.jpeg.identifier)
        } else {
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("photo-optimized.jpg").path))
        }
    }

    func testPNGOptimizationNeverChangesPixelsOrPublishesLargerFile() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("alpha.png")
        try makeImage(at: source, type: .png)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        let before = try Data(contentsOf: source)

        let outcome = try ImageOptimizationService().optimize(item, in: folder, preset: .balanced)

        XCTAssertEqual(try Data(contentsOf: source), before)
        if case .saved(let result) = outcome {
            XCTAssertLessThan(result.outputBytes, result.originalBytes)
            let output = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(output) as String?, UTType.png.identifier)
            let original = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
            let originalImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(original, 0, nil))
            let optimizedImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(output, 0, nil))
            XCTAssertEqual(originalImage.width, optimizedImage.width)
            XCTAssertEqual(originalImage.height, optimizedImage.height)
            let originalPixels = try XCTUnwrap(originalImage.dataProvider).data as Data?
            let optimizedPixels = try XCTUnwrap(optimizedImage.dataProvider).data as Data?
            XCTAssertEqual(originalPixels, optimizedPixels)
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(".orbitconvert-") })
    }

    func testPNGRejectsCustomQualityThatCannotBeApplied() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("alpha.png")
        try makeImage(at: source, type: .png)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)

        XCTAssertThrowsError(try ImageOptimizationService().optimize(item, in: folder,
                                                                    preset: .custom, jpegQuality: 0.5))
    }

    func testHEICOptimizationUsesInstalledImageIOEncoder() throws {
        guard (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(UTType.heic.identifier) == true else {
            throw XCTSkip("HEIC encoder unavailable on this Mac")
        }
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.heic")
        try makeImage(at: source, type: .heic, quality: 1.0)
        let before = try Data(contentsOf: source)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)

        let outcome = try ImageOptimizationService().optimize(item, in: folder, preset: .aggressive)

        XCTAssertEqual(try Data(contentsOf: source), before)
        if case .saved(let result) = outcome {
            XCTAssertLessThan(result.outputBytes, result.originalBytes)
            let output = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(output) as String?, UTType.heic.identifier)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeImage(at url: URL, type: UTType, quality: Double = 0.9) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.7))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
