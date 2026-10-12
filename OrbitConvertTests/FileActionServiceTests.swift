import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class FileActionServiceTests: XCTestCase {
    @MainActor
    func testConvertImageToPDFAndRenderPDFDispatchToRealServices() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try inspect(writeJPEG(in: folder, name: "photo.jpg"))
        let original = try Data(contentsOf: image.url)
        let service = FileActionService()
        let settings = makeSettings()

        let png = try await service.execute(FileAction(format: .png), for: image, selection: [image],
                                            in: folder, settings: settings)
        XCTAssertEqual(png.outputURLs.map(\.pathExtension), ["png"])
        XCTAssertTrue(png.message.hasPrefix("Saved "))

        let pdfReport = try await service.execute(FileAction(.imagePDF), for: image, selection: [image],
                                                  in: folder, settings: settings)
        let pdf = try inspect(XCTUnwrap(pdfReport.outputURLs.first))
        XCTAssertEqual(pdf.pageCount, 1)

        let progress = ProgressLog()
        let rendered = try await service.execute(FileAction(.pdfPNG), for: pdf, selection: [pdf], in: folder,
                                                 settings: settings, progress: { progress.append($0) })
        XCTAssertEqual(rendered.outputURLs.count, 1)
        XCTAssertEqual(progress.messages, ["Rendering page 1 of 1"])

        let extracted = try await service.execute(FileAction(.extractPages), for: pdf, selection: [pdf],
                                                  in: folder, settings: settings)
        XCTAssertEqual(PDFDocument(url: try XCTUnwrap(extracted.outputURLs.first))?.pageCount, 1)
        XCTAssertEqual(try Data(contentsOf: image.url), original)
    }

    @MainActor
    func testCompressReportsSavedOrNoReductionForImageAndPDF() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try inspect(writeJPEG(in: folder, name: "large.jpg", quality: 1))
        let original = try Data(contentsOf: image.url)
        let settings = makeSettings(preset: .aggressive)
        let service = FileActionService()

        let compressed = try await service.execute(FileAction(.compress), for: image, selection: [image],
                                                   in: folder, settings: settings)
        XCTAssertEqual(compressed.outputURLs.count, 1)
        XCTAssertNotNil(compressed.compression)
        XCTAssertTrue(compressed.message.hasPrefix("Optimized "))

        let pdfReport = try await service.execute(FileAction(.imagePDF), for: image, selection: [image],
                                                  in: folder, settings: makeSettings())
        let pdf = try inspect(XCTUnwrap(pdfReport.outputURLs.first))
        let pdfResult = try await service.execute(FileAction(.compress), for: pdf, selection: [pdf],
                                                  in: folder, settings: settings)
        XCTAssertTrue(pdfResult.message.hasPrefix("Optimized ") || pdfResult.message.hasPrefix("No useful size reduction"))
        XCTAssertEqual(pdfResult.outputURLs.isEmpty, pdfResult.compression == nil)
        XCTAssertEqual(try Data(contentsOf: image.url), original)
    }

    @MainActor
    func testCompressExplainsAlreadyCompressedJPEG() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try inspect(writeJPEG(in: folder, name: "small.jpg", quality: 0.5))
        let estimate = try XCTUnwrap(JPEGQualityEstimator.imageIOEquivalent(0.5))

        let report = try await FileActionService().execute(FileAction(.compress), for: image, selection: [image],
                                                            in: folder, settings: makeSettings())

        XCTAssertEqual(report.message, "Already compressed at about \(estimate)% quality. Original kept.")
        XCTAssertTrue(report.outputURLs.isEmpty)
    }

    private func makeSettings(preset: CompressionPreset = .balanced) -> FileActionSettings {
        FileActionSettings(jpegQuality: 0.9, stripMetadata: false, compressionPreset: preset,
                           pdfDPI: 72, pdfLayout: .fit, pageSelection: "all")
    }

    private func inspect(_ url: URL) throws -> FileItem {
        try XCTUnwrap(FileTypeService().inspect([url]).files.first)
    }

    private func writeJPEG(in folder: URL, name: String, quality: Double = 0.9) throws -> URL {
        let width = 1200, height = 800
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for band in 0..<40 {
            context.setFillColor(CGColor(red: CGFloat(band % 7) / 7, green: CGFloat(band % 5) / 5,
                                         blue: CGFloat(band % 3) / 3, alpha: 1))
            context.fill(CGRect(x: band * 30, y: (band * 17) % height, width: 60, height: 300))
        }
        let url = folder.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()),
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var messages: [String] { lock.withLock { stored } }
    func append(_ message: String) { lock.withLock { stored.append(message) } }
}
