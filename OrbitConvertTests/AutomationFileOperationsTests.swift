import XCTest
@testable import OrbitConvert

final class AutomationFileOperationsTests: XCTestCase {
    func testExtensionlessCopyAndCollisionPreserveExistingFiles() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        try Data("contents".utf8).write(to: source)
        try Data("existing".utf8).write(to: folder.appendingPathComponent("result"))
        let output = try await AutomationFileOperations().transfer(source: source, to: folder,
            name: "result", move: false, expected: FileFingerprint.read(source))
        XCTAssertEqual(output.lastPathComponent, "result-1")
        XCTAssertEqual(try Data(contentsOf: output), Data("contents".utf8))
        XCTAssertEqual(try Data(contentsOf: source), Data("contents".utf8))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("result")), Data("existing".utf8))
    }

    func testMovePublishesBeforeRemovingSource() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let output = try await AutomationFileOperations().transfer(source: source, to: folder,
            name: "renamed.txt", move: true, expected: FileFingerprint.read(source), willPublish: { candidate in
                XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            })
        XCTAssertEqual(try Data(contentsOf: output), Data("contents".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testSamePathIsUnchanged() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        try Data("contents".utf8).write(to: source)
        let expected = try FileFingerprint.read(source)
        let result = try await AutomationFileOperations().transfer(source: source, to: folder,
            name: "source", move: true, expected: expected)
        XCTAssertEqual(result, source)
        XCTAssertEqual(try FileFingerprint.read(source), expected)
    }

    func testInvalidNamesAndChangedSourceAreRejected() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        try Data("contents".utf8).write(to: source)
        let expected = try FileFingerprint.read(source)
        for name in ["", ".", "..", "a/b", "a:b", "a\n", String(repeating: "a", count: 256)] {
            do {
                _ = try await AutomationFileOperations().transfer(source: source, to: folder,
                    name: name, move: false, expected: expected)
                XCTFail("Accepted invalid name")
            } catch { }
        }
        try Data("changed".utf8).write(to: source)
        do {
            _ = try await AutomationFileOperations().transfer(source: source, to: folder,
                name: "result", move: true, expected: expected)
            XCTFail("Accepted changed source")
        } catch { XCTAssertEqual(error as? WatchError, .sourceChanged) }
    }

    func testCallbackMutationPreventsPublication() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        try Data("contents".utf8).write(to: source)
        do {
            _ = try await AutomationFileOperations().transfer(source: source, to: folder,
                name: "result", move: true, expected: FileFingerprint.read(source), willPublish: { _ in
                    try Data("new contents".utf8).write(to: source)
                })
            XCTFail("Published changed source")
        } catch { XCTAssertEqual(error as? WatchError, .sourceChanged) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("result").path))
        XCTAssertEqual(try Data(contentsOf: source), Data("new contents".utf8))
    }

    func testSymlinkSourceIsRejected() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        let alias = folder.appendingPathComponent("alias")
        try Data("contents".utf8).write(to: source)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        do {
            _ = try await AutomationFileOperations().transfer(source: alias, to: folder,
                name: "result", move: false, expected: FileFingerprint.read(source))
            XCTFail("Accepted symbolic link")
        } catch { XCTAssertEqual(error as? WatchError, .unavailableFile) }
    }

    func testSubstitutedSymlinkAncestorCannotPublishOrRemoveSource() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let nested = folder.appendingPathComponent("nested")
        let relocated = folder.appendingPathComponent("relocated")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let source = nested.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        do {
            _ = try await AutomationFileOperations().transfer(source: source, to: folder,
                name: "output.txt", move: true, expected: FileFingerprint.read(source), willPublish: { _ in
                    try FileManager.default.moveItem(at: nested, to: relocated)
                    try FileManager.default.createSymbolicLink(at: nested, withDestinationURL: relocated)
                })
            XCTFail("Followed substituted ancestor")
        } catch { XCTAssertEqual(error as? WatchError, .unavailableFile) }
        XCTAssertEqual(try Data(contentsOf: relocated.appendingPathComponent("source.txt")), Data("contents".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("output.txt").path))
    }

    func testConcurrentCopiesNeverOverwrite() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        try Data("contents".utf8).write(to: source)
        let expected = try FileFingerprint.read(source)
        let service = AutomationFileOperations()
        async let first = service.transfer(source: source, to: folder,
            name: "result.txt", move: false, expected: expected)
        async let second = service.transfer(source: source, to: folder,
            name: "result.txt", move: false, expected: expected)
        let outputs = try await [first, second]
        XCTAssertEqual(Set(outputs.map(\.lastPathComponent)), ["result.txt", "result-1.txt"])
        for output in outputs { XCTAssertEqual(try Data(contentsOf: output), Data("contents".utf8)) }
    }

    func testRejectedPublicationLeavesNoTemporaryFiles() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        try Data("contents".utf8).write(to: source)
        do {
            _ = try await AutomationFileOperations().transfer(source: source, to: folder,
                name: "result", move: true, expected: FileFingerprint.read(source), willPublish: { _ in
                    throw CancellationError()
                })
            XCTFail("Ignored cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["source"])
    }

    func testSamePathCopyCreatesNumberedCopy() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let expected = try FileFingerprint.read(source)
        let output = try await AutomationFileOperations().transfer(source: source, to: folder,
            name: "source.txt", move: false, expected: expected)
        XCTAssertEqual(output.lastPathComponent, "source-1.txt")
        XCTAssertEqual(try FileFingerprint.read(source), expected)
        XCTAssertEqual(try Data(contentsOf: output), Data("contents".utf8))
    }

    func testCustomCollisionNameUsesNextAvailableIndex() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let existing = folder.appendingPathComponent("photo_001.txt")
        try Data("existing".utf8).write(to: existing)
        let output = try await AutomationFileOperations().transfer(source: source, to: folder,
            name: "photo_001.txt", move: false, expected: FileFingerprint.read(source),
            collisionName: { "photo_" + String(format: "%03d", $0) + ".txt" })
        XCTAssertEqual(output.lastPathComponent, "photo_002.txt")
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        XCTAssertEqual(try Data(contentsOf: output), Data("contents".utf8))
    }

    func testFinishMoveRemovesOnlyUnchangedSourceAfterValidatedCopy() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        let output = folder.appendingPathComponent("output")
        try Data("contents".utf8).write(to: source)
        try Data("contents".utf8).write(to: output)
        try AutomationFileOperations().finishMove(source: source, expected: FileFingerprint.read(source),
            output: output, outputExpected: FileFingerprint.read(output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: output), Data("contents".utf8))
    }

    func testFinishMoveKeepsSourceWhenDestinationChanged() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        let output = folder.appendingPathComponent("output")
        try Data("contents".utf8).write(to: source)
        try Data("contents".utf8).write(to: output)
        let expected = try FileFingerprint.read(source)
        let outputExpected = try FileFingerprint.read(output)
        try Data("changed".utf8).write(to: output)
        XCTAssertThrowsError(try AutomationFileOperations().finishMove(source: source, expected: expected,
            output: output, outputExpected: outputExpected))
        XCTAssertEqual(try FileFingerprint.read(source), expected)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
