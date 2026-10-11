import XCTest
@testable import OrbitConvert

final class AutomationExecutionTests: XCTestCase {
    func testCopyRenameMovePreservesOriginalAndRunsInOrder() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let copies = root.appendingPathComponent("copies"), output = root.appendingPathComponent("output")
        for folder in [copies, output] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let source = root.appendingPathComponent("notes.txt")
        try Data("original".utf8).write(to: source)
        let rule = AutomationRule(name: "Organize", actions: [
            AutomationAction(kind: .copy, destinationBookmark: try bookmark(copies)),
            AutomationAction(kind: .rename, template: "'Note'_{i}.{ext}"),
            AutomationAction(kind: .move, destinationBookmark: try bookmark(output))])
        let files = AutomationFileOperations(trash: { try FileManager.default.removeItem(at: $0) })
        let result = await AutomationExecutionService(files: files).run(source, rule: rule)
        XCTAssertNil(result.checkpoint)
        XCTAssertEqual(result.details.steps.count, 3)
        XCTAssertEqual(result.outputURL?.lastPathComponent, "Note_1.txt")
        XCTAssertEqual(try Data(contentsOf: source), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("Note_1.txt")), Data("original".utf8))
    }

    func testFailureStopsAndRetryDoesNotRepeatRename() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let data = try bookmark(destination)
        let source = root.appendingPathComponent("notes.txt")
        try Data("original".utf8).write(to: source)
        let rule = AutomationRule(name: "Retry", actions: [AutomationAction(kind: .rename, template: "'Done'_{i}.{ext}"),
            AutomationAction(kind: .copy, destinationBookmark: data)])
        let first = await AutomationExecutionService().run(source, rule: rule, willPublish: { output in
            if output.deletingLastPathComponent().path == destination.path { throw ConversionError.cannotWriteFile }
        })
        let checkpoint = try XCTUnwrap(first.checkpoint)
        XCTAssertEqual(checkpoint.nextAction, 1)
        XCTAssertEqual(checkpoint.workingURL.lastPathComponent, "Done_1.txt")
        let retry = await AutomationExecutionService().run(source, rule: rule, resume: checkpoint)
        XCTAssertNil(retry.checkpoint)
        XCTAssertEqual(retry.outputURL?.lastPathComponent, "Done_1.txt")
        XCTAssertEqual(retry.details.steps.count, 2)
    }

    func testPreviewDoesNotChangeFilesAndReservesIncrementNames() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.txt", "b.txt"] { try Data(name.utf8).write(to: root.appendingPathComponent(name)) }
        let rule = AutomationRule(conditions: [AutomationCondition(field: .fileExtension, value: "txt")],
            actions: [AutomationAction(kind: .rename, template: "'Item'_{i}.{ext}")])
        var folder = WatchedFolder(displayName: "Test", bookmarkData: try bookmark(root))
        folder.rules = [rule]
        let items = try await AutomationPreviewService.preview(folder: folder)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].summary.contains("Item_1.txt"))
        XCTAssertTrue(items[1].summary.contains("Item_2.txt"))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["a.txt", "b.txt"])
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func bookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
