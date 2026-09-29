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

    private func makeTextPDF(at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        let text = NSAttributedString(string: "Selectable text", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(text)
        context.textPosition = CGPoint(x: 80, y: 700)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
    }
}
