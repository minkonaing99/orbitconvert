import XCTest
import UniformTypeIdentifiers
import PDFKit
import ImageIO
@testable import OrbitConvert

final class MarkdownConversionTests: XCTestCase {
    @MainActor
    func testRealExportsPreserveOriginalAndPaginate() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("notes.md")
        let text = "# Unicode café\n\n| Name | Value |\n| --- | --- |\n| Sample | 42 |\n\n```swift\nlet answer = 42\n```\n\n" + (1...150).map { "Paragraph \($0). Readable text for a multipage document.\n\n" }.joined()
        let before = Data(text.utf8)
        try before.write(to: url)
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)
        let service = MarkdownConversionService()
        let word: FileActionReport
        do { word = try await service.convert(file, toDOCX: true, in: folder) }
        catch { return XCTFail("DOCX phase: \(error)") }
        XCTAssertEqual(word.outputURLs.first?.pathExtension, "docx")
        let pdf: FileActionReport
        do { pdf = try await service.convert(file, toDOCX: false, in: folder) }
        catch { return XCTFail("PDF phase: \(error)") }
        let document = try XCTUnwrap(PDFDocument(url: try XCTUnwrap(pdf.outputURLs.first)))
        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("Paragraph 150") == true)
        XCTAssertTrue(document.string?.contains("Sample") == true)
        let firstPage = try XCTUnwrap(document.page(at: 0))
        let firstText = firstPage.string ?? ""
        let nameRange = (firstText as NSString).range(of: "Name")
        let valueRange = (firstText as NSString).range(of: "Value")
        XCTAssertNotEqual(nameRange.location, NSNotFound)
        XCTAssertNotEqual(valueRange.location, NSNotFound)
        let nameBounds = try XCTUnwrap(firstPage.selection(for: nameRange)).bounds(for: firstPage)
        let valueBounds = try XCTUnwrap(firstPage.selection(for: valueRange)).bounds(for: firstPage)
        XCTAssertGreaterThan(valueBounds.minX, nameBounds.maxX)
        XCTAssertEqual(nameBounds.midY, valueBounds.midY, accuracy: 2)
        XCTAssertTrue(document.string?.contains("let answer = 42") == true)
        XCTAssertEqual(try Data(contentsOf: url), before)
        let duplicate = try await service.convert(file, toDOCX: true, in: folder)
        XCTAssertEqual(duplicate.outputURLs.first?.lastPathComponent, "notes-1.docx")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".orbitconvert-") })
    }

    @MainActor
    func testPDFLinksRemainClickable() async throws {
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        let url = job.appendingPathComponent("links.md")
        try Data("# Links\n\n[Apple](https://www.apple.com)".utf8).write(to: url)
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)
        let result = try await MarkdownConversionService().convert(file, toDOCX: false, in: job)
        let pdf = try XCTUnwrap(PDFDocument(url: try XCTUnwrap(result.outputURLs.first)))
        let links = try XCTUnwrap(pdf.page(at: 0)).annotations.compactMap { ($0.action as? PDFActionURL)?.url }
        XCTAssertTrue(links.contains(try XCTUnwrap(URL(string: "https://www.apple.com"))))
    }

    func testMarkdownDetectionAndActions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("notes.md")
        try Data("# Notes\n\nHello".utf8).write(to: url)
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)
        XCTAssertTrue(file.isMarkdown)
        XCTAssertEqual(FileAction.common(for: [file]).map(\.kind), [.markdownPDF, .markdownDOCX])
        XCTAssertFalse(file.isImage)
    }

    func testUnavailableHelperFailsWithoutTouchingFiles() throws {
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        let original = job.appendingPathComponent("original.md")
        try Data("# Original".utf8).write(to: original)
        XCTAssertThrowsError(try BundledDocumentTool().run("untrusted", arguments: [], in: job))
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "# Original")
    }

    @MainActor
    func testCancelledPDFDoesNotCreateOutput() async throws {
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        let output = job.appendingPathComponent("cancelled.pdf")
        let rtf = Data(#"{\rtf1\ansi Hello}"#.utf8)
        let task = Task { try await MarkdownPDFRenderer.render(rtf, to: output) }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testAuthorizedImagesAreEmbeddedAndEscapesRejected() throws {
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        let image = job.appendingPathComponent("image.png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j6h8AAAAASUVORK5CYII=")?.write(to: image)
        let loader = MarkdownImageResources(root: job, sourceDirectory: job)
        XCTAssertTrue(try XCTUnwrap(loader.load("image.png")).dataURI.hasPrefix("data:image/png;base64,"))
        XCTAssertNil(try loader.load("../image.png"))
        XCTAssertNil(try loader.load("https://example.com/image.png"))
        XCTAssertNil(try loader.load(image.path))
        try FileManager.default.createSymbolicLink(at: job.appendingPathComponent("link.png"), withDestinationURL: image)
        XCTAssertNil(try loader.load("link.png"))
    }

    func testBinaryMarkdownRejected() throws {
        XCTAssertThrowsError(try MarkdownConversionService.validate(Data([0, 255, 10])))
    }

    @MainActor
    func testImagesExportToPDFAndDOCXWithCustomPDFPage() async throws {
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8,
            bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let png = job.appendingPathComponent("image.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let normalized = try XCTUnwrap(MarkdownImageResources(root: job, sourceDirectory: job).load("image.png"))
        let bytes = try XCTUnwrap(Data(base64Encoded: String(normalized.dataURI.dropFirst("data:image/png;base64,".count))))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 80)
        XCTAssertEqual(decoded.height, 40)
        XCTAssertNotEqual(decoded.alphaInfo, .none)
        let url = job.appendingPathComponent("illustrated.md")
        try Data("# Illustrated\\n\\n![Red](image.png)\\n\\n[Site](https://www.apple.com)".replacingOccurrences(of: "\\n", with: "\n").utf8).write(to: url)
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)
        let service = MarkdownConversionService()
        let word = try await service.convert(file, toDOCX: true, in: job, imageFolder: job)
        XCTAssertFalse(word.message.contains("omitted"))
        try FileManager.default.copyItem(at: try XCTUnwrap(word.outputURLs.first), to: job.appendingPathComponent("verify.docx"))
        try BundledDocumentTool().run("pandoc", arguments: ["--sandbox", "--from=docx", "--to=json", "--output=verify.json", "verify.docx"], in: job)
        XCTAssertTrue(try String(contentsOf: job.appendingPathComponent("verify.json"), encoding: .utf8).contains("\"Image\""))
        let pdf = try await service.convert(file, toDOCX: false, in: job, imageFolder: job,
            pdfStyle: MarkdownPDFStyle(bodySize: 14, margin: 60, useLetter: true, useSerif: true))
        let document = try XCTUnwrap(PDFDocument(url: try XCTUnwrap(pdf.outputURLs.first)))
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, 612, accuracy: 1)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, 792, accuracy: 1)
        var resources: CGPDFDictionaryRef?
        var objects: CGPDFDictionaryRef?
        let dictionary = try XCTUnwrap(page.pageRef?.dictionary)
        XCTAssertTrue(CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources))
        XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(resources), "XObject", &objects))
        XCTAssertGreaterThan(CGPDFDictionaryGetCount(try XCTUnwrap(objects)), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path))
        try Data("![](image.png)".utf8).write(to: url)
        let imageOnly = try await service.convert(file, toDOCX: true, in: job, imageFolder: job)
        XCTAssertFalse(imageOnly.outputURLs.isEmpty)
    }

    func testAggregateImagePixelBudget() throws {
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 2000, height: 2000, bitsPerComponent: 8,
            bytesPerRow: 8000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let imageURL = job.appendingPathComponent("large.png")
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let image: [String: Any] = ["t": "Image", "c": [["", [], []], [], ["large.png", ""]]]
        let ast: [String: Any] = ["pandoc-api-version": [1, 23, 1], "meta": [:],
            "blocks": [["t": "Para", "c": Array(repeating: image, count: 8)]]]
        let result = try MarkdownConversionService.sanitize(JSONSerialization.data(withJSONObject: ast),
            images: MarkdownImageResources(root: job, sourceDirectory: job))
        XCTAssertEqual(result.omittedImages, 2)
    }

    func testPDFStyleRejectsInvalidLimits() throws {
        XCTAssertThrowsError(try MarkdownPDFStyle(bodySize: .nan).validate())
        XCTAssertThrowsError(try MarkdownPDFStyle(margin: 0).validate())
        XCTAssertNoThrow(try MarkdownPDFStyle().validate())
    }

    func testSanitizerRemovesResourcesAndUnsafeLinks() throws {
        let ast = Data(#"{"pandoc-api-version":[1,23,1],"meta":{},"blocks":[{"t":"Para","c":[{"t":"Image","c":[["",[],[]],[{"t":"Str","c":"secret"}],["file:///etc/passwd",""]]},{"t":"Link","c":[["",[],[]],[{"t":"Str","c":"click"}],["javascript:alert(1)",""]]}]}]}"#.utf8)
        let result = try MarkdownConversionService.sanitize(ast)
        let value = String(decoding: result.data, as: UTF8.self)
        XCTAssertFalse(value.contains("file:///etc/passwd"))
        XCTAssertFalse(value.contains("javascript:"))
        XCTAssertEqual(result.omittedImages, 1)
        XCTAssertTrue(value.contains("secret"))
    }
}
