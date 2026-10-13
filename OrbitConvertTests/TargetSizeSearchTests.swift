import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class TargetSizeSearchTests: XCTestCase {
    func testFindsHighestFittingStepWithAtMostSixEncodes() throws {
        for threshold in stride(from: 100, through: 0, by: -5) {
            var calls = 0
            let found = TargetSizeCompressionService.highestFittingQuality { quality in
                calls += 1
                return quality <= threshold
            }
            XCTAssertEqual(found, threshold)
            XCTAssertLessThanOrEqual(calls, 6, "threshold \(threshold)")
        }
    }

    func testNothingFitsCostsOneEncodeAndErrorsPropagate() {
        var calls = 0
        XCTAssertNil(TargetSizeCompressionService.highestFittingQuality { _ in calls += 1; return false })
        XCTAssertEqual(calls, 1)
        XCTAssertThrowsError(try TargetSizeCompressionService.highestFittingQuality { _ in throw CancellationError() })
    }

    func testPicksSameQualityAsFullScanOnRealJPEG() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("photo.jpg")
        let image = try photo()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let target = Int64(try Data(contentsOf: url).count / 3)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let sizes = try stride(from: 100, through: 0, by: -5).map { quality -> (Int, Int64) in
            try? FileManager.default.removeItem(at: scratch)
            try ImageOptimizationService().encodeResized(decoded, properties: properties, format: .jpeg,
                preset: .custom, jpegQuality: Double(quality) / 100, to: scratch)
            return (quality, Int64(try Data(contentsOf: scratch).count))
        }
        let expected = sizes.first { $0.1 <= target }?.0
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)

        let report = try TargetSizeCompressionService().compress(file, in: folder, targetBytes: target)

        XCTAssertTrue(report.message.contains("\(try XCTUnwrap(expected))% \(ConversionFormat.jpeg.label) quality"),
                      report.message)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)),
                       ["photo.jpg", "photo-target-size.jpg"])
    }

    private func photo() throws -> CGImage {
        let width = 640, height = 480
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let wave = (sin(Double(x) / 19) + cos(Double(y) / 13) + 2) / 4
                context.setFillColor(red: wave, green: Double((x * 5 + y * 11) % 255) / 255, blue: 1 - wave, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }
}
