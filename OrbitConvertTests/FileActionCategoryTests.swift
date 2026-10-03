import XCTest
@testable import OrbitConvert

final class FileActionCategoryTests: XCTestCase {
    func testConversionAndToolSectionsUseActionKinds() {
        let conversionKinds: [FileAction.Kind] = [.convert(.jpeg), .imagePDF, .pdfJPEG, .pdfPNG]
        let toolKinds: [FileAction.Kind] = [.compress, .resize, .extractPages, .mergePDFs]

        XCTAssertTrue(conversionKinds.allSatisfy { FileAction($0).category == .conversion })
        XCTAssertTrue(toolKinds.allSatisfy { FileAction($0).category == .tool })
    }
}
