import XCTest
@testable import OrbitConvert

final class AutomationRenameTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1791659775)
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func render(_ pattern: String, name: String = "Photo", ext: String = "png", index: Int = 1) throws -> String {
        try AutomationRenameTemplate(pattern).render(originalName: name, fileExtension: ext,
            creationDate: date, modificationDate: nil, index: index, timeZone: utc)
    }

    func testCreationDateWinsAndMissingCreationUsesModifiedDate() throws {
        let template = try AutomationRenameTemplate("yy_MM_dd_HH_mm_ss")
        XCTAssertTrue(template.usesDate)
        XCTAssertFalse(template.usesIncrement)
        XCTAssertEqual(try template.render(originalName: "a", fileExtension: "jpg", creationDate: date,
            modificationDate: Date(timeIntervalSince1970: 0), index: 1, timeZone: utc), "26_10_10_19_16_15.jpg")
        XCTAssertEqual(try template.render(originalName: "a", fileExtension: "jpg", creationDate: nil,
            modificationDate: date, index: 1, timeZone: utc), "26_10_10_19_16_15.jpg")
        XCTAssertThrowsError(try template.render(originalName: "a", fileExtension: "jpg", creationDate: nil,
            modificationDate: nil, index: 1))
    }

    func testBraceDateTokensWorkIndividually() throws {
        XCTAssertEqual(try render("{yyyy}{MM}{dd}_{HH}{mm}{ss}"), "20261010_191615.png")
        XCTAssertEqual(try render("{dd}-{MM}-{yy}_{name}.{ext}"), "10-10-26_Photo.png")
        XCTAssertEqual(try render("'Shot' {HH}h{mm}"), "Shot 19h16.png")
        XCTAssertEqual(try render("yyyy-{MM}"), "2026-10.png", "Bare codes from older rules still work")
        XCTAssertTrue(try AutomationRenameTemplate("{ss}").usesDate)
        for pattern in ["{YYYY}", "{m}", "{yyy}", "{M}"] {
            XCTAssertThrowsError(try AutomationRenameTemplate(pattern), pattern)
        }
    }

    func testLiteralQuotesRepeatedNumberingAndExtensionlessNames() throws {
        XCTAssertEqual(try render("'Holiday yyyy'_{i}_{i:03}.{ext}", index: 12), "Holiday yyyy_12_012.png")
        XCTAssertEqual(try render("'Bob''s'_{name}"), "Bob's_Photo.png")
        XCTAssertEqual(try render("''{name}"), "'Photo.png")
        XCTAssertEqual(try render("{name}_{i}", ext: ""), "Photo_1")
        XCTAssertEqual(try render("{name}.PNG"), "Photo.PNG")
        XCTAssertEqual(try render("{name}.{ext}"), "Photo.png")
        XCTAssertTrue(try AutomationRenameTemplate("{i:03}").usesIncrement)
        XCTAssertEqual(try render("{i:03}", index: 1000), "1000.png")
    }

    func testMalformedAndUnsafeTemplatesAreRejected() throws {
        for pattern in ["", "{", "}", "{unknown}", "{i:00}", "{i:010}", "{i:-1}", "'unclosed",
                        "../{name}", "a/b", "a:b", ".hidden", "line\nname", "{ext}_suffix",
                        String(repeating: "x", count: 1_025), String(repeating: "x", count: 256)] {
            XCTAssertThrowsError(try AutomationRenameTemplate(pattern), pattern)
        }
        XCTAssertThrowsError(try render("{name}", name: "..", ext: ""))
        XCTAssertThrowsError(try render("{name}", name: "bad/name"))
        XCTAssertThrowsError(try render("{name}", index: 0))
        XCTAssertEqual(try render("'Safe'_{i}", name: "bad/name"), "Safe_1.png")
    }
}
