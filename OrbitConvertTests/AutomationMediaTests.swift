import AppKit
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

@MainActor
final class AutomationMediaTests: XCTestCase {
    func testConvertPreservesOriginalAndPublishesRequestedFormat() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try image(in: folder)
        let before = try Data(contentsOf: source)
        var action = AutomationAction()
        action.kind = .convert
        action.format = "tiff"
        let output = try await AutomationMediaService().perform(action, source: source,
            expected: FileFingerprint.read(source)) { candidate in
                XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.path))
            }
        XCTAssertEqual(output.url.pathExtension, "tiff")
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(FileTypeService().inspect([output.url]).files.first?.pixelWidth, 120)
    }

    func testResizeFitsBoundsAndKeepsOriginal() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try image(in: folder)
        var action = AutomationAction()
        action.kind = .resize
        action.width = 60
        action.height = 60
        let output = try await AutomationMediaService().perform(action, source: source,
            expected: FileFingerprint.read(source))
        let file = try XCTUnwrap(FileTypeService().inspect([output.url]).files.first)
        XCTAssertEqual(file.pixelWidth, 60)
        XCTAssertEqual(file.pixelHeight, 30)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testChangedOriginalAfterCallbackDoesNotPublish() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try image(in: folder)
        var action = AutomationAction()
        action.kind = .convert
        action.format = "tiff"
        do {
            _ = try await AutomationMediaService().perform(action, source: source,
                expected: FileFingerprint.read(source)) { _ in
                    try Data("changed".utf8).write(to: source)
                }
            XCTFail("Published after original changed")
        } catch { XCTAssertEqual(error as? WatchError, .sourceChanged) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("image.tiff").path))
    }

    func testFilesUnder800KBAreNotCompressed() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try image(in: folder)
        let before = try Data(contentsOf: source)
        var action = AutomationAction()
        action.kind = .compress
        action.replacement = .replaceOriginal

        let output = try await AutomationMediaService().perform(action, source: source,
                                                                expected: FileFingerprint.read(source))

        XCTAssertEqual(AutomationMediaService().minimumBytes, 800_000)
        XCTAssertEqual(output.url, source)
        XCTAssertEqual(output.savedBytes, 0)
        XCTAssertEqual(output.message, "Under 800 KB; not compressed")
        XCTAssertEqual(try Data(contentsOf: source), before)

        let text = folder.appendingPathComponent("note.txt")
        try Data("not an image".utf8).write(to: text)
        do {
            _ = try await AutomationMediaService().perform(action, source: text, expected: FileFingerprint.read(text))
            XCTFail("Unsupported files must still report an error, not a size skip")
        } catch {}
    }

    func testNoReductionKeepsCopyForFollowingActions() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try image(in: folder)
        let file = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        let small: URL
        switch try ImageOptimizationService().optimize(file, in: folder, preset: .lossless) {
        case .saved(let result): small = result.outputURL
        case .noReduction: small = source
        }
        var action = AutomationAction()
        action.kind = .compress
        action.preset = .lossless
        let output = try await AutomationMediaService().perform(action, source: small,
            expected: FileFingerprint.read(small))
        XCTAssertNotEqual(output.url, small)
        XCTAssertEqual(output.savedBytes, 0)
        XCTAssertEqual(try Data(contentsOf: output.url), try Data(contentsOf: small))
        action.replacement = .replaceOriginal
        let unchanged = try await AutomationMediaService().perform(action, source: small,
            expected: FileFingerprint.read(small))
        XCTAssertEqual(unchanged.url, small)
        XCTAssertEqual(unchanged.savedBytes, 0)
    }

    func testPDFMetadataRemovalKeepsOriginalAndPages() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let raster = try image(in: folder)
        let document = PDFDocument()
        let rasterImage = try XCTUnwrap(NSImage(contentsOf: raster))
        document.insert(try XCTUnwrap(PDFPage(image: rasterImage)), at: 0)
        document.documentAttributes = [PDFDocumentAttribute.authorAttribute: "Private Author"]
        let source = folder.appendingPathComponent("document.pdf")
        XCTAssertTrue(document.write(to: source))
        var action = AutomationAction()
        action.kind = .removeMetadata
        let output = try await AutomationMediaService().perform(action, source: source,
            expected: FileFingerprint.read(source))
        let cleaned = try XCTUnwrap(PDFDocument(url: output.url))
        XCTAssertEqual(cleaned.pageCount, 1)
        XCTAssertNil(cleaned.documentAttributes?[PDFDocumentAttribute.authorAttribute])
        XCTAssertEqual(PDFDocument(url: source)?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String, "Private Author")
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func image(in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("image.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 60, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
