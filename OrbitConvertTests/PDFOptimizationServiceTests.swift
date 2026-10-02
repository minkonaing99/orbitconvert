import CoreGraphics
import CoreText
import PDFKit
import XCTest
@testable import OrbitConvert

final class PDFOptimizationServiceTests: XCTestCase {
    func testNativeRewritePreservesTextAndOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("text.pdf")
        try makeTextPDF(at: source)
        let before = try Data(contentsOf: source)
        let file = try XCTUnwrap(FileTypeService().inspect([source]).files.first)

        let outcome = try PDFOptimizationService().optimize(file, in: folder,
                                                              options: PDFOptimizationOptions(preset: .lossless))

        XCTAssertEqual(try Data(contentsOf: source), before)
        if case .saved(let result) = outcome {
            let output = try XCTUnwrap(PDFDocument(url: result.outputURL))
            XCTAssertEqual(output.pageCount, 1)
            XCTAssertTrue(output.page(at: 0)?.string?.contains("Selectable text") == true)
            XCTAssertLessThan(result.outputBytes, result.originalBytes)
        } else {
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("text-optimized.pdf").path))
        }
    }

    func testRejectsUnimplementedExactDPIControls() throws {
        let options = PDFOptimizationOptions(preset: .balanced, targetDPI: 180)
        XCTAssertThrowsError(try options.validateForNativeBackend())
    }

    func testStrongerCompressionReducesImageHeavyPDFWithoutRasterizingText() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("scan.pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(source as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let pixels = (0..<(2000 * 2000 * 3)).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ ($0 / 1000)) }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: 2000, height: 2000, bitsPerComponent: 8, bitsPerPixel: 24,
            bytesPerRow: 6000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: [], provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        context.draw(image, in: CGRect(x: 40, y: 40, width: 532, height: 650))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Searchable scan text",
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)]))
        context.textPosition = CGPoint(x: 40, y: 740)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        let metadata = try XCTUnwrap(PDFDocument(url: source))
        metadata.documentAttributes = [PDFDocumentAttribute.authorAttribute: "Private author", PDFDocumentAttribute.titleAttribute: "Private title"]
        XCTAssertTrue(metadata.write(to: source))
        let before = try Data(contentsOf: source)
        let file = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        let outcome = try PDFOptimizationService().optimize(file, in: folder,
            options: PDFOptimizationOptions(preset: .aggressive, removeMetadata: true, strongerCompression: true))
        guard case .saved(let result) = outcome else { return XCTFail("Expected size reduction") }
        XCTAssertLessThan(result.outputBytes, result.originalBytes)
        XCTAssertNil(PDFDocument(url: result.outputURL)?.documentAttributes?[PDFDocumentAttribute.authorAttribute])
        XCTAssertNil(PDFDocument(url: result.outputURL)?.documentAttributes?[PDFDocumentAttribute.titleAttribute])
        XCTAssertEqual(PDFDocument(url: result.outputURL)?.string, PDFDocument(url: source)?.string)
        XCTAssertEqual(try Data(contentsOf: source), before)
    }

    func testStrongerCompressionRejectsAnnotationsAndKeepsOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("annotated.pdf")
        try makeTextPDF(at: source)
        let document = try XCTUnwrap(PDFDocument(url: source))
        document.page(at: 0)?.addAnnotation(PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 40, height: 40),
                                                         forType: .text, withProperties: nil))
        XCTAssertTrue(document.write(to: source))
        let before = try Data(contentsOf: source)
        XCTAssertThrowsError(try PDFOptimizationValidation.inspect(source, stronger: true))
        XCTAssertEqual(try Data(contentsOf: source), before)
    }

    func testEncryptedPDFRejectedByBothBackends() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("private.pdf")
        try makeTextPDF(at: source)
        let document = try XCTUnwrap(PDFDocument(url: source))
        XCTAssertTrue(document.write(to: source, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "reader"]))
        let before = try Data(contentsOf: source)
        XCTAssertThrowsError(try PDFOptimizationValidation.inspect(source, stronger: false))
        XCTAssertThrowsError(try PDFOptimizationValidation.inspect(source, stronger: true))
        XCTAssertEqual(try Data(contentsOf: source), before)
    }

    func testStrongerCompressionPreservesLinksAndNestedBookmarks() throws {
        let folder = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("navigation.pdf")
        let raw = folder.appendingPathComponent("raw.pdf")
        try makeTextPDF(at: raw, includeImage: true)
        try BundledDocumentTool().run("gs", arguments: ["-dSAFER", "-dBATCH", "-dNOPAUSE", "-dQUIET", "-sDEVICE=pdfwrite",
            "-dEncodeColorImages=false",
            "-sOutputFile=bookmarks.pdf", "-f", "raw.pdf", "-c",
            "[ /Title (Chapter) /Page 1 /View [/XYZ 0 792 null] /Count 1 /OUT pdfmark [ /Title (Detail) /Page 1 /View [/XYZ 80 700 null] /OUT pdfmark"], in: folder)
        let document = try XCTUnwrap(PDFDocument(url: folder.appendingPathComponent("bookmarks.pdf")))
        let page = try XCTUnwrap(document.page(at: 0))
        let link = PDFAnnotation(bounds: CGRect(x: 80, y: 695, width: 150, height: 22), forType: .link, withProperties: nil)
        link.action = PDFActionURL(url: try XCTUnwrap(URL(string: "https://www.apple.com")))
        page.addAnnotation(link)
        XCTAssertTrue(document.write(to: source))
        let reopened = try XCTUnwrap(PDFDocument(url: source))
        XCTAssertEqual(reopened.outlineRoot?.child(at: 0)?.child(at: 0)?.label, "Detail")
        let before = try Data(contentsOf: source)
        let file = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        let outcome = try PDFOptimizationService().optimize(file, in: folder,
            options: PDFOptimizationOptions(preset: .aggressive, strongerCompression: true))
        guard case .saved(let result) = outcome else { return XCTFail("Expected optimized navigation PDF") }
        let output = try XCTUnwrap(PDFDocument(url: result.outputURL))
        XCTAssertEqual((output.page(at: 0)?.annotations.first?.action as? PDFActionURL)?.url,
                       (page.annotations.first?.action as? PDFActionURL)?.url)
        XCTAssertEqual(output.outlineRoot?.child(at: 0)?.child(at: 0)?.label, "Detail")
        XCTAssertEqual(output.outlineRoot?.child(at: 0)?.child(at: 0)?.destination?.point, CGPoint(x: 80, y: 700))
        XCTAssertEqual(try Data(contentsOf: source), before)
    }

    private func makeTextPDF(at url: URL, includeImage: Bool = false) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        if includeImage {
            let pixels = (0..<(1600 * 1600 * 3)).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ ($0 / 1000)) }
            let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
            let image = try XCTUnwrap(CGImage(width: 1600, height: 1600, bitsPerComponent: 8, bitsPerPixel: 24,
                bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: [], provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent))
            context.draw(image, in: CGRect(x: 40, y: 40, width: 532, height: 600))
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        let text = NSAttributedString(string: "Selectable text", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(text)
        context.textPosition = CGPoint(x: 80, y: 700)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
    }
}
