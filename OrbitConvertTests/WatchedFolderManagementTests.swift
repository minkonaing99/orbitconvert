import XCTest
@testable import OrbitConvert

final class WatchedFolderManagementTests: XCTestCase {
    @MainActor
    func testRelinkUpdatesNameAndPathAndRejectsFiles() async throws {
        let first = try temporaryDirectory(), second = try temporaryDirectory()
        defer { [first, second].forEach { try? FileManager.default.removeItem(at: $0) } }
        let (controller, cleanup) = try makeController()
        defer { cleanup() }
        try controller.add([first], optimizeExisting: false, automation: true)
        let id = try XCTUnwrap(controller.folders.first?.id)
        XCTAssertTrue(controller.displayPath(for: id).hasSuffix(first.lastPathComponent))

        try controller.relink(id, to: second)
        XCTAssertEqual(controller.folders.first?.displayName, second.lastPathComponent)
        XCTAssertTrue(controller.displayPath(for: id).hasSuffix(second.lastPathComponent))

        let file = second.appendingPathComponent("file.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertThrowsError(try controller.relink(id, to: file)) { error in
            XCTAssertEqual(error as? WatchError, .unavailableFile)
        }
        XCTAssertEqual(controller.displayPath(for: UUID()), "Folder")
        controller.remove(id)
    }

    @MainActor
    func testExistingCountFindsOnlyEligibleFiles() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["a.jpg", "b.png", "c.pdf", ".hidden.jpg", "d.jpg.crdownload", "notes.txt"] {
            try Data("x".utf8).write(to: folder.appendingPathComponent(name))
        }
        let nested = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("x".utf8).write(to: nested.appendingPathComponent("e.jpg"))
        let (controller, cleanup) = try makeController()
        defer { cleanup() }
        let flat = await controller.existingCount(in: folder)
        let recursive = await controller.existingCount(in: folder, recursive: true)
        XCTAssertEqual(flat, 3)
        XCTAssertEqual(recursive, 4)
        let unknown = await controller.existingCount(for: UUID())
        XCTAssertEqual(unknown, 0)
    }

    @MainActor
    private func makeController() throws -> (WatchedFoldersController, () -> Void) {
        let suite = "OrbitConvert.FolderManagement.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = WatchedFoldersController(defaults: defaults)
        return (controller, {
            controller.setPaused(true)
            controller.folders.map(\.id).forEach(controller.remove)
            defaults.removePersistentDomain(forName: suite)
        })
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
