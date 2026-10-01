import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class PDFConversionServiceTests: XCTestCase {
    func testSharedSelectionExecutesMergeOnceAndConvertsOnlyChosenFiles() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try makeTextPDF(at: folder.appendingPathComponent("first.pdf"), text: "First")
        let second = try makeTextPDF(at: folder.appendingPathComponent("second.pdf"), text: "Second")
        let settings = FileActionSettings(jpegQuality: 0.9, stripMetadata: false,
            compressionPreset: .balanced, pdfDPI: 72, pdfLayout: .fit, pageSelection: "all")
        let service = SelectionActionService()
        let merged = try service.execute(FileAction(.mergePDFs), files: [second, first],
                                         directory: folder, settings: settings, progress: { _ in })
        XCTAssertEqual(merged.count, 1)
        let output = try XCTUnwrap(merged.first?.report?.outputURLs.first)
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("Second") == true)
        let converted = try service.execute(FileAction(.pdfPNG), files: [second],
                                            directory: folder, settings: settings, progress: { _ in })
        XCTAssertEqual(converted.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("second.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("first.png").path))
        try FileManager.default.removeItem(at: first.url)
        let partial = try service.execute(FileAction(.pdfPNG), files: [first, second],
                                          directory: folder, settings: settings, progress: { _ in })
        XCTAssertNotNil(partial.first?.errorMessage)
        XCTAssertEqual(partial.last?.report?.outputURLs.count, 1)
    }

    func testImagesToPDFPreservesOrderAndPageCount() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let images = try ["first.png", "second.png"].map { name -> FileItem in
            let url = folder.appendingPathComponent(name)
            try makeImage(at: url)
            return try XCTUnwrap(FileTypeService().inspect([url]).files.first)
        }

        let result = try PDFConversionService().imagesToPDF(images, in: folder, layout: .letter)

        XCTAssertEqual(result.outputURLs.count, 1)
        let pdf = try XCTUnwrap(PDFDocument(url: result.outputURLs[0]))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size.width, 612)
        XCTAssertEqual(pdf.page(at: 1)?.bounds(for: .mediaBox).size.height, 792)
    }

    func testPDFToJPEGAndPNGNamesEachPage() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try makePDF(at: folder.appendingPathComponent("report.pdf"), pages: 2)

        for format in [ConversionFormat.jpeg, .png] {
            let result = try PDFConversionService().renderPDF(file, as: format, in: folder, dpi: 150)
            XCTAssertEqual(result.outputURLs.count, 2)
            XCTAssertEqual(result.outputURLs.map(\.lastPathComponent),
                           ["report-page-001.\(format.fileExtension)", "report-page-002.\(format.fileExtension)"])
            for url in result.outputURLs {
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
                XCTAssertEqual(CGImageSourceGetType(source) as String?, format.typeIdentifier)
                let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
                XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 1275)
                XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 1650)
            }
        }
    }

    func testExtractAndMergeKeepPDFPages() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try makePDF(at: folder.appendingPathComponent("first.pdf"), pages: 3)
        let second = try makePDF(at: folder.appendingPathComponent("second.pdf"), pages: 2)
        let service = PDFConversionService()

        let extracted = try service.extractPages(first, pages: 2...3, in: folder)
        XCTAssertEqual(extracted.outputURLs[0].lastPathComponent, "first-pages-2-3.pdf")
        XCTAssertEqual(PDFDocument(url: extracted.outputURLs[0])?.pageCount, 2)

        let merged = try service.mergePDFs([first, second], in: folder)
        XCTAssertEqual(PDFDocument(url: merged.outputURLs[0])?.pageCount, 5)
    }

    func testPageSelectionParsingRejectsInvalidRanges() throws {
        let service = FileActionService()
        XCTAssertEqual(try service.parsePages("all", pageCount: 8), 1...8)
        XCTAssertEqual(try service.parsePages("4-7", pageCount: 8), 4...7)
        XCTAssertEqual(try service.parsePages("3", pageCount: 8), 3...3)
        XCTAssertThrowsError(try service.parsePages("9", pageCount: 8))
        XCTAssertThrowsError(try service.parsePages("7-4", pageCount: 8))
        XCTAssertThrowsError(try service.parsePages("../1", pageCount: 8))
    }

    func testRotatedPageExportsLandscapeImage() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("rotated.pdf")
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        page.rotation = 90
        document.insert(page, at: 0)
        XCTAssertTrue(document.write(to: url))
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)

        let result = try PDFConversionService().renderPDF(file, as: .png, in: folder, dpi: 150)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURLs[0] as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 1650)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 1275)
    }

    func testExtractAndMergePreserveSelectableText() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try makeTextPDF(at: folder.appendingPathComponent("first.pdf"), text: "First chapter")
        let second = try makeTextPDF(at: folder.appendingPathComponent("second.pdf"), text: "Second chapter")

        let extracted = try PDFConversionService().extractPages(first, pages: 1...1, in: folder)
        XCTAssertTrue(PDFDocument(url: extracted.outputURLs[0])?.page(at: 0)?.string?.contains("First chapter") == true)
        let merged = try PDFConversionService().mergePDFs([first, second], in: folder)
        let document = try XCTUnwrap(PDFDocument(url: merged.outputURLs[0]))
        XCTAssertTrue(document.page(at: 0)?.string?.contains("First chapter") == true)
        XCTAssertTrue(document.page(at: 1)?.string?.contains("Second chapter") == true)
    }

    func testCorruptPDFCannotPublishImages() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("document.pdf")
        let file = try makePDF(at: url, pages: 1)
        let corrupt = Data("not a PDF".utf8)
        try corrupt.write(to: url)

        XCTAssertThrowsError(try PDFConversionService().renderPDF(file, as: .png, in: folder))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("document.png").path))
    }

    func testPDFToPNGIncludesVisibleAnnotation() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = try makePDF(at: folder.appendingPathComponent("plain.pdf"), pages: 1)
        let annotatedURL = folder.appendingPathComponent("annotated.pdf")
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        let annotation = PDFAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 200),
                                       forType: .square, withProperties: nil)
        annotation.color = .red
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = 12
        page.addAnnotation(annotation)
        document.insert(page, at: 0)
        XCTAssertTrue(document.write(to: annotatedURL))
        let annotated = try XCTUnwrap(FileTypeService().inspect([annotatedURL]).files.first)

        let plainURL = try PDFConversionService().renderPDF(plain, as: .png, in: folder, dpi: 72).outputURLs[0]
        let renderedURL = try PDFConversionService().renderPDF(annotated, as: .png, in: folder, dpi: 72).outputURLs[0]
        let plainSource = try XCTUnwrap(CGImageSourceCreateWithURL(plainURL as CFURL, nil))
        let annotatedSource = try XCTUnwrap(CGImageSourceCreateWithURL(renderedURL as CFURL, nil))
        let plainImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(plainSource, 0, nil))
        let annotatedImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(annotatedSource, 0, nil))
        XCTAssertNotEqual(plainImage.dataProvider?.data as Data?, annotatedImage.dataProvider?.data as Data?)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeImage(at url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func makePDF(at url: URL, pages: Int) throws -> FileItem {
        let document = PDFDocument()
        for index in 0..<pages {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        XCTAssertTrue(document.write(to: url))
        return try XCTUnwrap(FileTypeService().inspect([url]).files.first)
    }

    private func makeTextPDF(at url: URL, text: String) throws -> FileItem {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        context.textPosition = CGPoint(x: 80, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        context.endPDFPage()
        context.closePDF()
        return try XCTUnwrap(FileTypeService().inspect([url]).files.first)
    }
}
