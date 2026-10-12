import XCTest
@testable import OrbitConvert

final class FileIntakeServiceTests: XCTestCase {
    func testMixedBatchKeepsReadableFilesAndReportsInvalidURLs() throws {
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

        XCTAssertEqual(result.files.map(\.name), ["first.png", "notes.txt", "second.jpg"],
                       "Folder contents already selected are not added twice")
        XCTAssertEqual(result.issues.count, 2)
        XCTAssertTrue(result.issues.allSatisfy { !$0.message.isEmpty })
    }

    func testFolderExpandsToSupportedTopLevelFilesSortedByName() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["b.jpg", "a.png", "notes.md", "doc.pdf", "readme.txt", ".hidden.png", "movie.jpg.crdownload"] {
            try Data([0x01]).write(to: folder.appendingPathComponent(name))
        }
        let nested = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data([0x01]).write(to: nested.appendingPathComponent("c.png"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.png"),
                                                   withDestinationURL: folder.appendingPathComponent("a.png"))

        let result = FileIntakeService().inspect([folder])
        XCTAssertEqual(result.files.map(\.name), ["a.png", "b.jpg", "doc.pdf", "notes.md"])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testFolderWithoutSupportedFilesIsReported() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([0x01]).write(to: folder.appendingPathComponent("readme.txt"))
        let result = FileIntakeService().inspect([folder])
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.issues.map(\.message), ["This folder has no supported images, PDFs or Markdown files."])
    }

    func testLargeFolderAddsFirstFiveHundredAndReportsTotal() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0..<502 {
            try Data([0x01]).write(to: folder.appendingPathComponent(String(format: "image-%03d.png", index)))
        }
        let result = FileIntakeService().inspect([folder])
        XCTAssertEqual(result.files.count, 500)
        XCTAssertEqual(result.files.last?.name, "image-499.png")
        XCTAssertEqual(result.issues.map(\.message), ["This folder has 502 supported files; the first 500 were added."])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
