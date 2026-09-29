import XCTest
@testable import OrbitConvert

final class FileIntakeServiceTests: XCTestCase {
    func testMixedBatchKeepsImagesAndReportsEachRejectedURL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let png = directory.appendingPathComponent("first.png")
        let jpeg = directory.appendingPathComponent("second.jpg")
        let text = directory.appendingPathComponent("notes.txt")
        for url in [png, jpeg, text] {
            try Data([0x01]).write(to: url)
        }

        let result = FileIntakeService().inspect([
            png,
            text,
            directory,
            directory.appendingPathComponent("missing.heic"),
            URL(string: "https://example.com/photo.png")!,
            jpeg
        ])

        XCTAssertEqual(result.files.map(\.name), ["first.png", "second.jpg"])
        XCTAssertEqual(result.issues.count, 4)
        XCTAssertTrue(result.issues.allSatisfy { !$0.message.isEmpty })
    }
}
