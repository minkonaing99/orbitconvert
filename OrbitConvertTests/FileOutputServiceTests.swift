import XCTest
@testable import OrbitConvert

final class FileOutputServiceTests: XCTestCase {
    func testCollisionKeepsExistingFilesAndUsesNextName() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.png")
        let existing = folder.appendingPathComponent("photo.jpg")
        try Data("source".utf8).write(to: source)
        try Data("existing".utf8).write(to: existing)
        let service = FileOutputService()
        let temporary = try service.makeTemporaryFile(in: folder)
        try Data("converted".utf8).write(to: temporary)

        let output = try service.publish(temporary, beside: source, as: .jpeg, in: folder)

        XCTAssertEqual(output.lastPathComponent, "photo-1.jpg")
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        XCTAssertEqual(try Data(contentsOf: output), Data("converted".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    @MainActor
    func testConcurrentPublicationNeverOverwrites() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.png")
        try Data("original".utf8).write(to: source)
        let service = FileOutputService()
        let first = try service.makeTemporaryFile(in: folder)
        let second = try service.makeTemporaryFile(in: folder)
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)

        async let firstOutput = service.publish(first, beside: source, as: .jpeg, in: folder)
        async let secondOutput = service.publish(second, beside: source, as: .jpeg, in: folder)
        let outputs = try await [firstOutput, secondOutput]

        XCTAssertEqual(Set(outputs.map(\.lastPathComponent)), ["photo.jpg", "photo-1.jpg"])
        XCTAssertEqual(Set(try outputs.map { try Data(contentsOf: $0) }), [Data("one".utf8), Data("two".utf8)])
        XCTAssertEqual(try Data(contentsOf: source), Data("original".utf8))
    }

    func testInvalidDestinationFailsWithoutChangingSource() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.png")
        try Data("source".utf8).write(to: source)

        XCTAssertThrowsError(try FileOutputService().makeTemporaryFile(in: source))
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
    }

    func testTemporaryOutputIsPrivateAndCleanedUp() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = FileOutputService()
        let temporary = try service.makeTemporaryFile(in: folder)
        let privateFolder = temporary.deletingLastPathComponent()
        let attributes = try FileManager.default.attributesOfItem(atPath: privateFolder.path)

        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.uint16Value, 0o700)
        try Data("converted".utf8).write(to: temporary)
        service.removeTemporaryFile(temporary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: privateFolder.path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
