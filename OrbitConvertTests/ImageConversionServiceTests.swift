import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class ImageConversionServiceTests: XCTestCase {
    func testPNGToJPEGFlattensTransparencyAndKeepsExistingFile() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.png")
        try writeImage(to: source, type: .png, transparent: true)
        let existing = folder.appendingPathComponent("photo.jpg")
        try Data("existing".utf8).write(to: existing)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)

        let result = try ImageConversionService().convert(item, to: .jpeg, in: folder)

        XCTAssertEqual(result.outputURL.lastPathComponent, "photo-1.jpg")
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        let output = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(output) as String?, UTType.jpeg.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(output, 0, nil))
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 64)
        let sample = try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: 48, y: 32)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(sample.redComponent, 0.8)
        XCTAssertGreaterThan(sample.greenComponent, 0.8)
        XCTAssertGreaterThan(sample.blueComponent, 0.8)
    }

    func testJPEGToPNGAndPNGToTIFF() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for (input, output) in [(UTType.jpeg, ConversionFormat.png), (.png, .tiff)] {
            let source = folder.appendingPathComponent(UUID().uuidString + "." + (input.preferredFilenameExtension ?? "img"))
            try writeImage(to: source, type: input)
            let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
            let result = try ImageConversionService().convert(item, to: output, in: folder)
            let image = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(image) as String?, output.typeIdentifier)
            let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(image, 0, nil))
            XCTAssertEqual(pixels.width, 64)
            XCTAssertEqual(pixels.height, 64)
        }
    }

    func testRejectsInvalidQualityAndChangedSource() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.png")
        try writeImage(to: source, type: .png)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        XCTAssertThrowsError(try ImageConversionService().convert(item, to: .jpeg, in: folder,
                                                                   options: ConversionOptions(jpegQuality: .nan)))
        try Data("damaged".utf8).write(to: source)
        XCTAssertThrowsError(try ImageConversionService().convert(item, to: .jpeg, in: folder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("photo.jpg").path))
    }

    func testHEICToJPEGWhenEncoderIsAvailable() throws {
        guard (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(UTType.heic.identifier) == true else {
            throw XCTSkip("HEIC encoder is unavailable on this Mac")
        }
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.heic")
        try writeImage(to: source, type: .heic)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)

        let result = try ImageConversionService().convert(item, to: .jpeg, in: folder)

        let output = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(output) as String?, UTType.jpeg.identifier)
        XCTAssertEqual(CGImageSourceGetCount(output), 1)
    }

    func testMetadataCanBePreservedOrRemoved() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.tiff")
        let metadata = [kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFArtist as String: "OrbitConvert Test"]]
        try writeImage(to: source, type: .tiff, properties: metadata)
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)

        let kept = try ImageConversionService().convert(item, to: .png, in: folder)
        let stripped = try ImageConversionService().convert(item, to: .png, in: folder,
                                                             options: ConversionOptions(stripMetadata: true))

        XCTAssertEqual(tiffArtist(at: kept.outputURL), "OrbitConvert Test")
        XCTAssertNil(tiffArtist(at: stripped.outputURL))
    }

    private func tiffArtist(at url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] else { return nil }
        return tiff[kCGImagePropertyTIFFArtist as String] as? String
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeImage(to url: URL, type: UTType, transparent: Bool = false,
                            properties: [String: Any] = [:]) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        if !transparent {
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        } else {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        }
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
