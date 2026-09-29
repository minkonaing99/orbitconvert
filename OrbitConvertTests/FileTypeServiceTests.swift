import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class FileTypeServiceTests: XCTestCase {
    func testDetectsImageBytesDespiteMisleadingExtension() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("photo.txt")
        try writeImage(to: image, type: .png)

        let result = FileTypeService().inspect([image])

        XCTAssertEqual(result.files.count, 1)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.files.first?.contentTypeIdentifier, UTType.png.identifier)
        XCTAssertEqual(result.files.first?.fileExtension, "txt")
        XCTAssertEqual(result.files.first?.pixelWidth, 600)
        XCTAssertEqual(result.files.first?.pixelHeight, 400)
        XCTAssertGreaterThan(result.files.first?.fileSize ?? 0, 0)
        XCTAssertNotNil(result.files.first?.creationDate)
        let thumbnail = try XCTUnwrap(result.files.first?.thumbnailData)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let preview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), 256)
        XCTAssertTrue(result.files[0].supportedConversions.contains(.jpeg))
        XCTAssertFalse(result.files[0].supportedConversions.contains(.png))
    }

    func testRejectsCorruptUnsupportedAndMultipleFrameFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let corrupt = directory.appendingPathComponent("broken.png")
        let text = directory.appendingPathComponent("notes.txt")
        let multi = directory.appendingPathComponent("multi.tiff")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: corrupt)
        try Data("plain text".utf8).write(to: text)
        try writeImage(to: multi, type: .tiff, count: 2)

        let result = FileTypeService().inspect([corrupt, text, multi])

        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.issues.count, 3)
        XCTAssertTrue(result.issues.allSatisfy { !$0.message.isEmpty })
    }

    func testDetectsJPEGAndTIFFAndFiltersOutputsByInstalledEncoders() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let jpeg = directory.appendingPathComponent("jpeg-with-png-name.png")
        let tiff = directory.appendingPathComponent("image.tiff")
        try writeImage(to: jpeg, type: .jpeg)
        try writeImage(to: tiff, type: .tiff)

        let result = FileTypeService().inspect([jpeg, tiff])

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.files.map(\.contentTypeIdentifier), [UTType.jpeg.identifier, UTType.tiff.identifier])
        let available = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        for file in result.files {
            XCTAssertTrue(file.supportedConversions.allSatisfy { available.contains($0.typeIdentifier) })
            XCTAssertFalse(file.supportedConversions.contains { $0.typeIdentifier == file.contentTypeIdentifier })
        }
    }

    func testDetectsHEICWhenSystemEncoderIsAvailable() throws {
        let available = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        guard available.contains(UTType.heic.identifier) else {
            throw XCTSkip("HEIC encoder unavailable on this Mac")
        }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let heic = directory.appendingPathComponent("photo.heic")
        try writeImage(to: heic, type: .heic)

        let result = FileTypeService().inspect([heic])

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.files.first?.contentTypeIdentifier, UTType.heic.identifier)
        XCTAssertTrue(result.files.first?.supportedConversions.contains(.jpeg) == true)
    }

    func testMixedBatchKeepsValidImageAndReportsUnsupportedSibling() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = directory.appendingPathComponent("image.png")
        let text = directory.appendingPathComponent("notes.txt")
        try writeImage(to: png, type: .png)
        try Data("not an image".utf8).write(to: text)

        let intake = FileIntakeService().inspect([png, text])
        let inspected = FileTypeService().inspect(intake.files.map(\.url))

        XCTAssertTrue(intake.issues.isEmpty)
        XCTAssertEqual(inspected.files.map(\.fileName), ["image.png"])
        XCTAssertEqual(inspected.issues.map(\.name), ["notes.txt"])
    }

    func testDetectsPDFAndItsPageCount() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document.dat")
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        document.insert(PDFPage(), at: 1)
        XCTAssertTrue(document.write(to: url))

        let result = FileTypeService().inspect([url])

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.files.first?.contentTypeIdentifier, UTType.pdf.identifier)
        XCTAssertEqual(result.files.first?.pageCount, 2)
        XCTAssertFalse(result.files.first?.thumbnailData.isEmpty ?? true)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeImage(to url: URL, type: UTType, count: Int = 1) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, count, nil))
        for _ in 0..<count { CGImageDestinationAddImage(destination, image, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
