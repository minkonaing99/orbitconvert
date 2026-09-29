import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class BatchConversionServiceTests: XCTestCase {
    func testCommonFormatsAndBatchConversionKeepSources() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = ["first.png", "second.png"].map { folder.appendingPathComponent($0) }
        for url in urls { try writePNG(at: url) }
        let files = FileTypeService().inspect(urls).files
        let originals = try urls.map { try Data(contentsOf: $0) }

        XCTAssertEqual(BatchConversionService.commonFormats(for: files), [.jpeg])
        let result = BatchConversionService().convert(files, to: .jpeg, in: folder)

        XCTAssertEqual(result.outputURLs.count, 2)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, originals)
        XCTAssertTrue(result.outputURLs.allSatisfy { $0.pathExtension == "jpg" })
    }

    private func writePNG(at url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
