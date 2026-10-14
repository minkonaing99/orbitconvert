import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class PhotoPNGTests: XCTestCase {
    func testOpaquePhotoLikePNGBecomesJPEGOnlyWhenAllowed() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try write(photo(opaque: true), name: "photo.png", in: folder)

        guard case .saved(let kept) = try ImageOptimizationService().optimize(file, in: folder, preset: .balanced)
        else { return XCTFail("Lossless PNG result expected") }
        XCTAssertEqual(kept.outputURL.pathExtension, "png")

        guard case .saved(let converted) = try ImageOptimizationService().optimize(file, in: folder, preset: .balanced,
                                                                                convertPhotos: true)
        else { return XCTFail("JPEG result expected") }
        XCTAssertEqual(converted.outputURL.pathExtension, "jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(converted.outputURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual([image.width, image.height], [1000, 800])
        XCTAssertLessThan(converted.outputBytes, kept.outputBytes - 100_000)
    }

    func testClearJPEGWinSkipsTheExpensivePNGPass() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try write(photo(opaque: true), name: "photo.png", in: folder)
        let original = Int64(try XCTUnwrap(file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize))
        let temporary = folder.appendingPathComponent("candidate")

        XCTAssertTrue(try ImageOptimizationService().jpegClearlyWins(source(file), originalSize: original,
                                                                     preset: .balanced, removeMetadata: false, to: temporary))
        XCTAssertEqual(CGImageSourceGetType(try XCTUnwrap(CGImageSourceCreateWithURL(temporary as CFURL, nil))) as String?,
                       UTType.jpeg.identifier)
        let shot = try write(screenshot(), name: "shot.png", in: folder)
        XCTAssertFalse(try ImageOptimizationService().jpegClearlyWins(source(shot), originalSize: original,
            preset: .balanced, removeMetadata: false, to: folder.appendingPathComponent("other")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("other").path))
    }

    func testTransparentScreenshotLosslessAndSmallSavingsStayPNG() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transparent = try write(photo(opaque: false), name: "alpha.png", in: folder)
        let shot = try write(screenshot(), name: "shot.png", in: folder)
        let small = try write(photo(opaque: true, width: 120, height: 90), name: "small.png", in: folder)
        let photoFile = try write(photo(opaque: true), name: "photo.png", in: folder)

        for (file, preset) in [(transparent, CompressionPreset.balanced), (shot, .balanced), (small, .balanced),
                               (photoFile, .lossless)] {
            if case .saved(let result) = try ImageOptimizationService().optimize(file, in: folder, preset: preset,
                                                                                 convertPhotos: true) {
                XCTAssertEqual(result.outputURL.pathExtension, "png", file.fileName)
            }
        }
        XCTAssertTrue(ImageOptimizationService.isPhotoLike(try source(photoFile)))
        XCTAssertFalse(ImageOptimizationService.isPhotoLike(try source(shot)))
        XCTAssertFalse(ImageOptimizationService.isPhotoLike(try source(transparent)), "Transparency is never dropped")
    }

    func testRuleReplaceOriginalPublishesJPEGAndTrashesPNG() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try write(photo(opaque: true), name: "camera.png", in: folder)
        let trashed = Trashed()
        var action = AutomationAction()
        action.kind = .compress
        action.replacement = .replaceOriginal
        action.convertPhotos = true
        let service = AutomationMediaService(minimumBytes: 0, trash: { url in
            trashed.urls.append(url)
            try FileManager.default.removeItem(at: url)
        })

        let output = try await service.perform(action, source: file.url, expected: FileFingerprint.read(file.url))

        XCTAssertEqual(output.url.lastPathComponent, "camera.jpg")
        XCTAssertEqual(trashed.urls.map(\.lastPathComponent), ["camera.png"])
        XCTAssertGreaterThan(output.savedBytes, 100_000)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["camera.jpg"])
    }

    func testTrashFailureKeepsBothFilesAndContinuesWithJPEG() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try write(photo(opaque: true), name: "camera.png", in: folder)
        var action = AutomationAction()
        action.kind = .compress
        action.replacement = .moveOriginalToTrash
        action.convertPhotos = true
        let service = AutomationMediaService(minimumBytes: 0, trash: { _ in throw CocoaError(.fileWriteNoPermission) })

        let output = try await service.perform(action, source: file.url, expected: FileFingerprint.read(file.url))

        XCTAssertEqual(output.url.lastPathComponent, "camera.jpg")
        XCTAssertTrue(output.message.contains("original PNG kept"), output.message)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["camera.png", "camera.jpg"])
    }

    func testRulesSavedBeforeConversionDecodeWithItOff() throws {
        let saved = try JSONEncoder().encode(AutomationAction())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        object.removeValue(forKey: "convertPhotos")
        let decoded = try JSONDecoder().decode(AutomationAction.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.convertPhotos)
    }

    private final class Trashed: @unchecked Sendable { var urls: [URL] = [] }

    private func photo(opaque: Bool, width: Int = 1000, height: Int = 800) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 7
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                for channel in 0..<3 {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    let base = [x * 255 / width, y * 255 / height, (x + y) * 127 / (width + height) + 64][channel]
                    bytes[index + channel] = UInt8(max(0, min(255, base + Int(seed >> 24) % 41 - 20)))
                }
                if !opaque, x < 40 { bytes[index + 3] = 128 }
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .last
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func screenshot() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        // 60 flat bars score about 6% unique colors, like real UI screenshots (2-16%).
        for index in 0..<60 {
            context.setFillColor(CGColor(red: CGFloat(index % 9) / 9, green: 0.4, blue: CGFloat(index % 4) / 4, alpha: 1))
            context.fill(CGRect(x: (index * 37) % 1200, y: (index * 53) % 800, width: 140, height: 14))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func write(_ image: CGImage, name: String, in folder: URL) throws -> FileItem {
        let url = folder.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return try XCTUnwrap(FileTypeService().inspect([url]).files.first)
    }

    private func source(_ file: FileItem) throws -> CGImageSource {
        try XCTUnwrap(CGImageSourceCreateWithURL(file.url as CFURL, nil))
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
