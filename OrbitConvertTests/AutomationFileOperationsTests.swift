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

    func testMoveSendsSourceToTrashInsteadOfDeleting() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let trashed = TrashRecorder()
        let output = try await AutomationFileOperations(trash: trashed.trash).transfer(source: source,
            to: folder, name: "moved.txt", move: true, expected: FileFingerprint.read(source))
        XCTAssertEqual(trashed.urls, [source])
        XCTAssertEqual(try Data(contentsOf: output), Data("contents".utf8))
    }

    func testFinishMoveSendsSourceToTrash() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        let output = folder.appendingPathComponent("output")
        try Data("contents".utf8).write(to: source)
        try Data("contents".utf8).write(to: output)
        let trashed = TrashRecorder()
        try AutomationFileOperations(trash: trashed.trash).finishMove(source: source,
            expected: FileFingerprint.read(source), output: output, outputExpected: FileFingerprint.read(output))
        XCTAssertEqual(trashed.urls, [source])
    }

    func testTrashFailureKeepsSourceAndReportsPublishedCopy() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let failing = AutomationFileOperations(trash: { _ in throw CocoaError(.featureUnsupported) })
        do {
            _ = try await failing.transfer(source: source, to: folder, name: "moved.txt", move: true,
                expected: FileFingerprint.read(source))
            XCTFail("Trash failure was not reported")
        } catch let AutomationTransferError.publishedCopy(output, _) {
            XCTAssertEqual(try Data(contentsOf: output), Data("contents".utf8))
        }
        XCTAssertEqual(try Data(contentsOf: source), Data("contents".utf8))
    }

    func testRenameKeepsSameFileWithoutCopyOrTrash() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let before = try FileFingerprint.read(source)
        let trashed = TrashRecorder()
        let output = try await AutomationFileOperations(trash: trashed.trash).rename(source: source,
            to: "renamed.txt", expected: before)
        XCTAssertEqual(output.lastPathComponent, "renamed.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let after = try FileFingerprint.read(output)
        XCTAssertEqual([after.device, after.inode], [before.device, before.inode])
        XCTAssertEqual(trashed.urls, [])
    }

    func testRenameCollisionKeepsExistingFile() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        let existing = folder.appendingPathComponent("taken.txt")
        try Data("contents".utf8).write(to: source)
        try Data("existing".utf8).write(to: existing)
        let output = try await AutomationFileOperations().rename(source: source, to: "taken.txt",
            expected: FileFingerprint.read(source))
        XCTAssertEqual(output.lastPathComponent, "taken-1.txt")
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        XCTAssertEqual(try Data(contentsOf: output), Data("contents".utf8))
    }

    func testRenameUsesCustomCollisionName() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        try Data("existing".utf8).write(to: folder.appendingPathComponent("Item_1.txt"))
        let output = try await AutomationFileOperations().rename(source: source, to: "Item_1.txt",
            expected: FileFingerprint.read(source), collisionName: { "Item_\($0).txt" })
        XCTAssertEqual(output.lastPathComponent, "Item_2.txt")
    }

    func testRenameToCurrentNameIsUnchanged() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let output = try await AutomationFileOperations().rename(source: source, to: "source.txt",
            expected: FileFingerprint.read(source))
        XCTAssertEqual(output.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: source), Data("contents".utf8))
    }

    func testRenameRejectsChangedSourceAndInvalidName() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let expected = try FileFingerprint.read(source)
        do {
            _ = try await AutomationFileOperations().rename(source: source, to: "../escape.txt", expected: expected)
            XCTFail("Accepted path separator")
        } catch { XCTAssertEqual(error as? ConversionError, .invalidDestination) }
        try Data("changed".utf8).write(to: source)
        do {
            _ = try await AutomationFileOperations().rename(source: source, to: "renamed.txt", expected: expected)
            XCTFail("Renamed a changed source")
        } catch { XCTAssertEqual(error as? WatchError, .sourceChanged) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testRenameChangingOnlyLetterCaseKeepsName() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.jpg")
        try Data("contents".utf8).write(to: source)
        let output = try await AutomationFileOperations().rename(source: source, to: "Photo.jpg",
            expected: FileFingerprint.read(source))
        XCTAssertEqual(output.lastPathComponent, "Photo.jpg")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Photo.jpg"])
        XCTAssertEqual(try Data(contentsOf: output), Data("contents".utf8))
    }

    func testUnsupportedVolumeErrorIsExplained() {
        XCTAssertEqual(FileOutputService.writeError(for: ENOTSUP), .unsupportedVolume)
        XCTAssertTrue(ConversionError.unsupportedVolume.localizedDescription.contains("another folder"))
    }

    func testDefaultTrashMovesFileToTrash() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("orbit-trash-test-\(UUID().uuidString).txt")
        try Data("contents".utf8).write(to: source)
        let trashed = try AutomationFileOperations.moveToTrash(source)
        defer { if let trashed { try? FileManager.default.removeItem(at: trashed) } }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try trashed.map { try Data(contentsOf: $0) }, Data("contents".utf8))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class TrashRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []
    var urls: [URL] { lock.withLock { recorded } }

    func trash(_ url: URL) throws {
        lock.withLock { recorded.append(url) }
        try FileManager.default.removeItem(at: url)
    }
}
