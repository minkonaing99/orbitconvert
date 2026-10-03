import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class FileActionTests: XCTestCase {
    func testSharedActionsRequireEverySelectedFile() {
        let jpeg = FileItem(url: URL(fileURLWithPath: "/tmp/a.jpg"), fileName: "a.jpg", fileExtension: "jpg", contentTypeIdentifier: UTType.jpeg.identifier, contentTypeName: "JPEG", fileSize: 10, creationDate: nil, pixelWidth: 1, pixelHeight: 1, pageCount: nil, thumbnailData: Data(), supportedConversions: [.png, .tiff])
        let png = FileItem(url: URL(fileURLWithPath: "/tmp/b.png"), fileName: "b.png", fileExtension: "png", contentTypeIdentifier: UTType.png.identifier, contentTypeName: "PNG", fileSize: 20, creationDate: nil, pixelWidth: 1, pixelHeight: 1, pageCount: nil, thumbnailData: Data(), supportedConversions: [.jpeg, .tiff])
        XCTAssertTrue(FileAction.common(for: []).isEmpty)
        let actions = FileAction.common(for: [jpeg, png])
        XCTAssertTrue(actions.contains(FileAction(.compress)))
        XCTAssertTrue(actions.contains { $0.id == "resize" })
        XCTAssertTrue(actions.contains(FileAction(format: .tiff)))
        XCTAssertTrue(actions.contains(FileAction(.imagePDF)))
        XCTAssertFalse(actions.contains(FileAction(format: .jpeg)))
        XCTAssertFalse(actions.contains(FileAction(format: .png)))
    }

    func testPDFAndImageActionsAreDistinct() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdfURL = folder.appendingPathComponent("document.pdf")
        let pdf = PDFDocument()
        pdf.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdf.write(to: pdfURL))
        let item = try XCTUnwrap(FileTypeService().inspect([pdfURL]).files.first)

        let actions = FileAction.available(for: item, selection: [item])

        XCTAssertTrue(actions.contains { $0.id == "compress" })
        XCTAssertTrue(actions.contains { $0.id == "pdf-jpeg" })
        XCTAssertTrue(actions.contains { $0.id == "pdf-png" })
        XCTAssertTrue(actions.contains { $0.id == "extract-pages" })
        XCTAssertFalse(actions.contains { $0.id == "image-pdf" })
        XCTAssertFalse(actions.contains { $0.id == "resize" })
        let shared = FileAction.common(for: [item, item])
        XCTAssertTrue(shared.contains(FileAction(.mergePDFs)))
        XCTAssertFalse(shared.contains(FileAction(.extractPages)))
    }
}
