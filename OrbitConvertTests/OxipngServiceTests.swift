import XCTest
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
@testable import OrbitConvert

final class OxipngServiceTests: XCTestCase {
    @MainActor
    func testCancelledJobDoesNotCreateOutput() async {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let job = Task {
            try OxipngService().optimize(source: output.appendingPathExtension("png"),
                                        destination: output, preset: .balanced)
        }
        job.cancel()
        do {
            try await job.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testBundledOptimizerExists() {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: OxipngService.executableURL.path))
    }

    func testPreservesMetadataAlphaAndRejectsDestinationCollision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        let output = directory.appendingPathComponent("optimized.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(context.makeImage()),
            [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "Keep this metadata"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let original = try Data(contentsOf: source)
        try OxipngService().optimize(source: source, destination: output, preset: .balanced)
        let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [String: Any])
        let metadata = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any]
        XCTAssertEqual(metadata?[kCGImagePropertyPNGDescription as String] as? String, "Keep this metadata")
        let optimized = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        let input = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
        XCTAssertEqual(try pixels(optimized), try pixels(XCTUnwrap(CGImageSourceCreateImageAtIndex(input, 0, nil))))
        XCTAssertLessThan(try Data(contentsOf: output).count, original.count)
        let saved = try Data(contentsOf: output)
        XCTAssertThrowsError(try OxipngService().optimize(source: source, destination: output, preset: .aggressive))
        XCTAssertEqual(try Data(contentsOf: output), saved)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testEncoderCacheCanBeRemovedButContentCredentialsAreProtected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let original = try Data(contentsOf: source)
        for name in ["iDOT", "caBX"] {
            let bytes = original.dropLast(12) + chunk(name) + original.suffix(12)
            try bytes.write(to: source)
            let output = directory.appendingPathComponent(name + ".png")
            if name == "iDOT" {
                try OxipngService().optimize(source: source, destination: output, preset: .balanced)
                XCTAssertNotNil(CGImageSourceCreateWithURL(output as CFURL, nil))
            } else {
                XCTAssertThrowsError(try OxipngService().optimize(source: source, destination: output, preset: .balanced)) {
                    XCTAssertEqual($0 as? OptimizationError, .protectedMetadata)
                }
                XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            }
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
        var corrupt = original
        corrupt[29] ^= 0xff
        try corrupt.write(to: source)
        let failedOutput = directory.appendingPathComponent("failed.png")
        XCTAssertThrowsError(try OxipngService().optimize(source: source, destination: failedOutput, preset: .balanced))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedOutput.path))
        XCTAssertEqual(try Data(contentsOf: source), corrupt)
    }

    private func chunk(_ name: String) -> Data {
        let payload = Data(name.utf8) + Data(repeating: 0, count: 8)
        var crc: UInt32 = 0xffffffff
        for byte in payload {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        crc ^= 0xffffffff
        return Data([0, 0, 0, 8]) + payload + Data([UInt8(crc >> 24), UInt8((crc >> 16) & 255), UInt8((crc >> 8) & 255), UInt8(crc & 255)])
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
    }

    func testRejectsTruncatedPNGWithoutTouchingSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("broken.png")
        let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10, 255, 255, 255, 255])
        try bytes.write(to: source)
        XCTAssertThrowsError(try OxipngService().optimize(source: source,
            destination: directory.appendingPathComponent("output.png"), preset: .balanced))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
}
