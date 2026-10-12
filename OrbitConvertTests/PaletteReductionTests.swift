import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class PaletteReductionTests: XCTestCase {
    func testScreenshotLikePNGBecomesSmallerPalettePNG() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writePNG(screenshotLike(), to: folder.appendingPathComponent("shot.png"))
        let output = folder.appendingPathComponent("palette.png")
        XCTAssertTrue(try PngquantService().quantize(source, to: output))
        XCTAssertLessThan(try size(output), try size(source))
        XCTAssertTrue(try chunks(output).contains("PLTE"))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(
            try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil)), 0, nil))
        XCTAssertEqual([image.width, image.height], [1200, 800])
    }

    func testNoisyImageBelowQualityFloorIsSkippedWithoutOutput() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writePNG(noise(), to: folder.appendingPathComponent("noise.png"))
        let output = folder.appendingPathComponent("palette.png")
        XCTAssertFalse(try PngquantService().quantize(source, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testOptimizeUsesPaletteOnlyWhenAllowed() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try writePNG(screenshotLike(), to: folder.appendingPathComponent("shot.png"))
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)
        guard case .saved(let lossless) = try ImageOptimizationService().optimize(file, in: folder, preset: .balanced)
        else { return XCTFail("Expected lossless reduction") }
        XCTAssertFalse(try chunks(lossless.outputURL).contains("PLTE"))
        guard case .saved(let palette) = try ImageOptimizationService().optimize(file, in: folder, preset: .balanced,
                                                                              palette: true)
        else { return XCTFail("Expected palette reduction") }
        XCTAssertTrue(try chunks(palette.outputURL).contains("PLTE"))
        XCTAssertLessThan(palette.outputBytes, lossless.outputBytes)
    }

    func testPaletteFallsBackToLosslessWhenQualityTooLow() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try writePNG(noise(), to: folder.appendingPathComponent("noise.png"))
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)
        let outcome = try ImageOptimizationService().optimize(file, in: folder, preset: .balanced, palette: true)
        switch outcome {
        case .saved(let result): XCTAssertFalse(try chunks(result.outputURL).contains("PLTE"))
        case .noReduction: break
        }
    }

    func testTargetSizeUsesPaletteToFitScreenshots() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try writePNG(screenshotLike(), to: folder.appendingPathComponent("shot.png"))
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)
        guard case .saved(let lossless) = try ImageOptimizationService().optimize(file, in: folder, preset: .balanced)
        else { return XCTFail("Expected lossless reduction") }
        let target = lossless.outputBytes / 2
        XCTAssertThrowsError(try TargetSizeCompressionService().compress(file, in: folder, targetBytes: target))
        let report = try TargetSizeCompressionService().compress(file, in: folder, targetBytes: target, palette: true)
        XCTAssertLessThanOrEqual(try XCTUnwrap(report.compression).outputBytes, target)
        XCTAssertTrue(report.message.contains("palette"), report.message)
    }

    func testOversizedOrBrokenInputIsSkippedInsteadOfFailing() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var header = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13]) + Data("IHDR".utf8)
        header += Data([0, 0, 0xC3, 0x50, 0, 0, 0xC3, 0x50, 8, 6, 0, 0, 0, 0, 0, 0, 0])
        let huge = folder.appendingPathComponent("huge.png")
        try header.write(to: huge)
        XCTAssertFalse(try PngquantService().quantize(huge, to: folder.appendingPathComponent("a.png")),
                       "50000 x 50000 exceeds the pixel cap and is never passed to pngquant")
        let broken = folder.appendingPathComponent("broken.png")
        try (Data([137, 80, 78, 71, 13, 10, 26, 10]) + Data(repeating: 7, count: 64)).write(to: broken)
        XCTAssertFalse(try PngquantService().quantize(broken, to: folder.appendingPathComponent("b.png")),
                       "A helper failure means skip, so the lossless path can still run")
    }

    private func screenshotLike() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        for index in 0..<300 {
            context.setFillColor(CGColor(red: CGFloat(index % 9) / 9, green: 0.4, blue: CGFloat(index % 4) / 4, alpha: 1))
            context.fill(CGRect(x: (index * 37) % 1200, y: (index * 53) % 800, width: 140, height: 14))
            context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.6))
            context.fillEllipse(in: CGRect(x: (index * 71) % 1200, y: (index * 29) % 800, width: 9, height: 9))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func noise() throws -> CGImage {
        let width = 256, height = 256
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 12_345
        for index in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<3 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                bytes[index + channel] = UInt8(truncatingIfNeeded: seed >> 24)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func writePNG(_ image: CGImage, to url: URL) throws -> URL {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func size(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    private func chunks(_ url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        var names: [String] = [], offset = 8
        while offset + 8 <= data.count {
            let length = data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            names.append(String(decoding: data[offset + 4..<offset + 8], as: UTF8.self))
            offset += 12 + length
        }
        return names
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
