import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class FileActionTests: XCTestCase {
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
    }
}
