import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class BatchOptimizationServiceTests: XCTestCase {
    func testBatchContinuesAfterOneMissingFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstURL = folder.appendingPathComponent("first.png")
        let secondURL = folder.appendingPathComponent("second.png")
        try makePNG(at: firstURL)
        try makePNG(at: secondURL)
        let items = FileTypeService().inspect([firstURL, secondURL]).files
        XCTAssertEqual(items.count, 2)
        try FileManager.default.removeItem(at: secondURL)

        let result = BatchOptimizationService().optimize(items, in: folder, preset: .balanced)

        XCTAssertEqual(result.attemptedCount, 2)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.successCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
    }

    func testLosslessBatchNeverReencodesJPEGLossily() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("photo.png")
        try makePNG(at: png)
        let image = try XCTUnwrap(FileTypeService().inspect([png]).files.first)
        let jpeg = try ImageConversionService().convert(image, to: .jpeg, in: folder).outputURL
        let original = try Data(contentsOf: jpeg)
        let item = try XCTUnwrap(FileTypeService().inspect([jpeg]).files.first)

        let result = BatchOptimizationService().optimize([item], in: folder, preset: .lossless)

        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.saved.count, 0)
        XCTAssertEqual(try Data(contentsOf: jpeg), original)
    }

    private func makePNG(at url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64,
                                            bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
