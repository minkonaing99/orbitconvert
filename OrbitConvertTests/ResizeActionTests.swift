import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class ResizeActionTests: XCTestCase {
    @MainActor
    func testResizeRunsThroughSelectionPipelineAndKeepsBothOriginals() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = try ["first", "second"].map { name in
            let url = folder.appendingPathComponent(name + ".png")
            try makePNG(at: url)
            return url
        }
        let originals = try urls.map { try Data(contentsOf: $0) }
        let files = FileTypeService().inspect(urls).files
        XCTAssertEqual(files.count, 2)
        let settings = FileActionSettings(resizeOptions: ResizeOptions(preset: .half),
            jpegQuality: 0.9, stripMetadata: false, compressionPreset: .balanced,
            pdfDPI: 150, pdfLayout: .fit, pageSelection: "all")

        let entries = try await SelectionActionService().execute(FileAction(.resize), files: files,
            directory: folder, settings: settings, progress: { _ in })

        XCTAssertEqual(entries.count, 2)
        for (index, entry) in entries.enumerated() {
            XCTAssertNil(entry.errorMessage)
            let report = try XCTUnwrap(entry.report)
            XCTAssertTrue(report.message.contains("160 x 120 px"))
            let result = try XCTUnwrap(report.compression)
            XCTAssertTrue(result.outputURL.lastPathComponent.contains("-resized"))
            XCTAssertLessThan(result.outputBytes, result.originalBytes)
            XCTAssertEqual(try Data(contentsOf: urls[index]), originals[index])
        }
    }

    func testUnsupportedTypesDoNotAdvertiseResize() {
        for type in [UTType.pdf.identifier, UTType.tiff.identifier, "net.daringfireball.markdown"] {
            let file = FileItem(url: URL(fileURLWithPath: "/tmp/test"), fileName: "test",
                fileExtension: "", contentTypeIdentifier: type, contentTypeName: "test",
                fileSize: 1, creationDate: nil, pixelWidth: 1, pixelHeight: 1,
                pageCount: type == UTType.pdf.identifier ? 1 : nil,
                thumbnailData: Data(), supportedConversions: [])
            XCTAssertFalse(FileAction.available(for: file, selection: [file]).contains(FileAction(.resize)))
        }
    }

    private func makePNG(at url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for y in 0..<240 {
            for x in 0..<320 {
                context.setFillColor(CGColor(red: CGFloat((x * 13 + y * 7) % 256) / 255,
                    green: CGFloat((x * 3 + y * 17) % 256) / 255, blue: 0.6, alpha: 0.7))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
