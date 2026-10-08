import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class TargetSizeCompressionTests: XCTestCase {
    func testMeetsTargetPreservesDimensionsAndOriginalAndAvoidsCollisions() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try fixture(folder)
        let original = try Data(contentsOf: file.url)
        let target = Int64(original.count / 2)
        for _ in 0..<2 {
            let report = try TargetSizeCompressionService().compress(file, in: folder, targetBytes: target)
            let result = try XCTUnwrap(report.compression)
            XCTAssertLessThanOrEqual(result.outputBytes, target)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 320)
            XCTAssertEqual(image.height, 240)
        }
        XCTAssertEqual(try Data(contentsOf: file.url), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 3)
    }

    func testAlreadyBelowTargetDoesNotReencode() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try fixture(folder)
        let report = try TargetSizeCompressionService().compress(file, in: folder, targetBytes: 2_000_000)
        XCTAssertTrue(report.outputURLs.isEmpty)
        XCTAssertTrue(report.message.contains("Already"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
    }

    func testImpossibleAndInvalidTargetsLeaveNoOutput() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try fixture(folder)
        for target: Int64 in [0, -1, 1] {
            XCTAssertThrowsError(try TargetSizeCompressionService().compress(file, in: folder, targetBytes: target))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
    }

    @MainActor
    func testSelectionDispatch() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try fixture(folder)
        let settings = FileActionSettings(targetBytes: file.fileSize / 2, jpegQuality: 0.9,
            stripMetadata: false, compressionPreset: .balanced, pdfDPI: 150,
            pdfLayout: .fit, pageSelection: "all")
        let entries = try await SelectionActionService().execute(FileAction(.compressToSize),
            files: [file], directory: folder, settings: settings, progress: { _ in })
        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries.first?.report?.compression)
    }

    func testTargetInputValidation() throws {
        XCTAssertEqual(try TargetSizeOptions.bytes(amount: "2", megabytes: true), 2_000_000)
        XCTAssertEqual(try TargetSizeOptions.bytes(amount: "250", megabytes: false), 250_000)
        XCTAssertEqual(try TargetSizeOptions.bytes(amount: "0.5", megabytes: true), 500_000)
        for input in ["", "abc", "NaN", "inf", "-1", "0", "1e100", "0.0000001"] {
            XCTAssertThrowsError(try TargetSizeOptions.bytes(amount: input, megabytes: true))
        }
    }

    func testActionOnlyAvailableForJPEG() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let jpeg = try fixture(folder)
        XCTAssertTrue(FileAction.common(for: [jpeg]).contains(FileAction(.compressToSize)))
        let png = FileItem(url: jpeg.url, fileName: "fake.png", fileExtension: "png",
            contentTypeIdentifier: UTType.png.identifier, contentTypeName: "PNG", fileSize: 1,
            creationDate: nil, pixelWidth: 1, pixelHeight: 1, pageCount: nil,
            thumbnailData: Data(), supportedConversions: [])
        XCTAssertFalse(FileAction.common(for: [jpeg, png]).contains(FileAction(.compressToSize)))
        XCTAssertThrowsError(try TargetSizeCompressionService().compress(png, in: folder, targetBytes: 100))
    }

    func testMetadataPolicyPreservesOrientation() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try fixture(folder, metadata: true)
        for strip in [false, true] {
            let report = try TargetSizeCompressionService().compress(file, in: folder,
                targetBytes: file.fileSize / 2, removeMetadata: strip)
            let url = try XCTUnwrap(report.outputURLs.first)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
            XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 6)
            let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
            XCTAssertEqual(tiff?[kCGImagePropertyTIFFArtist as String] as? String, strip ? nil : "Orbit Test")
        }
    }

    @MainActor
    func testCancellationCreatesNoOutput() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try fixture(folder)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TargetSizeCompressionService().compress(file, in: folder, targetBytes: 10_000)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
    }

    func testCorruptSourceAndInvalidDestinationAreRejected() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try fixture(folder)
        XCTAssertThrowsError(try TargetSizeCompressionService().compress(file,
            in: URL(string: "https://example.com")!, targetBytes: 100))
        try Data("broken".utf8).write(to: file.url)
        XCTAssertThrowsError(try TargetSizeCompressionService().compress(file, in: folder, targetBytes: 100))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
    }

    func testResizeFloorForLandscapePortraitSquareAndSmallOriginals() throws {
        for (width, height) in [(3840, 2160), (2160, 3840), (2160, 2160), (2000, 1200)] {
            let sizes = TargetSizeOptions.resizeDimensions(width: width, height: height)
            let last = try XCTUnwrap(sizes.last)
            XCTAssertEqual(min(last.width, last.height), 1080)
            XCTAssertTrue(sizes.allSatisfy { min($0.width, $0.height) >= 1080 })
            XCTAssertTrue(sizes.allSatisfy { $0.width <= width && $0.height <= height })
            XCTAssertEqual(Double(last.width) / Double(last.height), Double(width) / Double(height), accuracy: 0.002)
        }
        XCTAssertTrue(TargetSizeOptions.resizeDimensions(width: 1920, height: 1080).isEmpty)
        XCTAssertTrue(TargetSizeOptions.resizeDimensions(width: 800, height: 600).isEmpty)
    }

    func testResizesWhenQualityAloneCannotFitAndStopsAtFloor() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try fixture(folder, metadata: true, width: 2160, height: 1440)
        let original = try Data(contentsOf: file.url)
        let baseline = try ImageOptimizationService().optimize(file, in: folder, preset: .custom, jpegQuality: 0)
        guard case .saved(let minimum) = baseline else { return XCTFail("Expected smaller baseline") }
        let target = minimum.outputBytes * 4 / 5
        try FileManager.default.removeItem(at: minimum.outputURL)
        let report = try TargetSizeCompressionService().compress(file, in: folder, targetBytes: target)
        let result = try XCTUnwrap(report.compression)
        XCTAssertLessThanOrEqual(result.outputBytes, target)
        let inspected = try XCTUnwrap(FileTypeService().inspect([result.outputURL]).files.first)
        XCTAssertEqual(min(inspected.pixelWidth, inspected.pixelHeight), 1080)
        XCTAssertTrue(report.message.contains("resized"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 1)
        XCTAssertEqual(try Data(contentsOf: file.url), original)
        try FileManager.default.removeItem(at: result.outputURL)
        XCTAssertThrowsError(try TargetSizeCompressionService().compress(file, in: folder, targetBytes: 1))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
    }

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func fixture(_ folder: URL, metadata: Bool = false, width: Int = 320, height: Int = 240) throws -> FileItem {
        let url = folder.appendingPathComponent("photo.jpg")
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for y in 0..<height {
            for x in 0..<width {
                context.setFillColor(CGColor(red: CGFloat((x * 13 + y * 7) % 256) / 255,
                    green: CGFloat((x * 3 + y * 17) % 256) / 255, blue: 0.6, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 1.0]
        if metadata {
            properties[kCGImagePropertyOrientation as String] = 6
            properties[kCGImagePropertyTIFFDictionary as String] = [kCGImagePropertyTIFFArtist as String: "Orbit Test"]
        }
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return try XCTUnwrap(FileTypeService().inspect([url]).files.first)
    }
}
