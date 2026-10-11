import Foundation
import XCTest
@testable import OrbitConvert

final class AutomationWatchTests: XCTestCase {
    func testGenericFileRunsOnlyFirstMatchingRule() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.txt")
        try Data("arbitrary text".utf8).write(to: source)
        let first = renameRule(name: "First", prefix: "first")
        let second = renameRule(name: "Second", prefix: "second")
        let watched = try folder(root, rules: [first, second])
        let result = await AutomationWatchService.process(source, folder: watched, willPublish: { _ in })
        XCTAssertEqual(result.activity.outcome, .optimized)
        XCTAssertEqual(result.activity.automation?.ruleName, "First")
        XCTAssertEqual(result.activity.automation?.steps.count, 1)
        XCTAssertEqual(result.outputURL?.lastPathComponent, "first_report.txt")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(result.outputURL)), Data("arbitrary text".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("second_first_report.txt").path))
    }

    func testApprovedPreviewRejectsFileChangedBeforeRun() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.txt")
        try Data("before".utf8).write(to: source)
        let watched = try folder(root, rules: [renameRule()])
        let previews = try await AutomationPreviewService.preview(folder: watched)
        let approved = try XCTUnwrap(previews.first)
        try Data("changed after preview".utf8).write(to: source)
        let result = await AutomationWatchService.process(source, folder: watched, approved: approved, willPublish: { _ in })
        XCTAssertEqual(result.activity.outcome, .failed)
        XCTAssertNil(result.outputURL)
        XCTAssertEqual(try Data(contentsOf: source), Data("changed after preview".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["report.txt"])
    }

    func testPreviewReservesNamesWithoutChangingFiles() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.txt")
        let second = root.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: first)
        try Data("b".utf8).write(to: second)
        let before = try [FileFingerprint.read(first), FileFingerprint.read(second)]
        var rule = renameRule()
        rule.actions = [AutomationAction(kind: .rename, template: "'shared'_{i}.{ext}")]
        let previews = try await AutomationPreviewService.preview(folder: folder(root, rules: [rule]))
        XCTAssertEqual(previews.count, 2)
        XCTAssertTrue(previews[0].summary.contains("shared_1.txt"))
        XCTAssertTrue(previews[1].summary.contains("shared_2.txt"))
        XCTAssertTrue(previews.allSatisfy { $0.issue == nil && $0.rule?.id == rule.id })
        XCTAssertEqual(try [FileFingerprint.read(first), FileFingerprint.read(second)], before)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["a.txt", "b.txt"])
    }

    func testPreviewHonorsPerRuleSubfolderScope() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("root".utf8).write(to: root.appendingPathComponent("top.txt"))
        try Data("nested".utf8).write(to: nested.appendingPathComponent("child.txt"))
        let topOnly = renameRule()
        var recursivePDF = renameRule(name: "PDF")
        recursivePDF.includeSubfolders = true
        recursivePDF.conditions = [AutomationCondition(field: .fileExtension, comparison: .equals, value: "pdf")]
        let previews = try await AutomationPreviewService.preview(folder: folder(root, rules: [topOnly, recursivePDF]))
        XCTAssertEqual(previews.count, 2)
        XCTAssertEqual(previews.first { $0.url.lastPathComponent == "top.txt" }?.rule?.id, topOnly.id)
        XCTAssertNil(previews.first { $0.url.lastPathComponent == "child.txt" }?.rule)
    }

    func testUnavailableDocumentTextDoesNotMatchNegativeCondition() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0, 255, 1]).write(to: root.appendingPathComponent("binary.bin"))
        var rule = renameRule()
        rule.conditions = [AutomationCondition(field: .text, comparison: .notContains, value: "secret")]
        let items = try await AutomationPreviewService.preview(folder: folder(root, rules: [rule]))
        let preview = try XCTUnwrap(items.first)
        XCTAssertNil(preview.rule)
        XCTAssertNotNil(preview.issue)
        XCTAssertTrue(preview.summary.contains("No matching rule"))
    }

    func testLegacyHistoryDecodesWithoutAutomationAndNewHistoryRetainsSavings() throws {
        let old = WatchActivity(fileName: "photo.jpg", outcome: .optimized, originalBytes: 1_000, outputBytes: 600)
        let encoded = try JSONEncoder().encode(old)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "automation")
        let legacy = try JSONDecoder().decode(WatchActivity.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.automation)
        XCTAssertEqual(legacy.savingsBytes, 400)
        let step = AutomationStepRecord(action: "Compress", inputName: "photo.jpg", outputName: "photo-optimized.jpg",
            destination: "/example", message: "Compressed", failed: false, savedBytes: 250)
        let details = AutomationRunDetails(ruleName: "Resize and compress", finalName: "photo-optimized.jpg",
            destination: "/example", steps: [step], dateFallback: true, compressionOriginalBytes: 1_000, compressionSavedBytes: 250)
        let activity = WatchActivity(fileName: "photo.jpg", outcome: .optimized,
            originalBytes: 3_000, outputBytes: 500, automation: details)
        let decoded = try JSONDecoder().decode(WatchActivity.self, from: JSONEncoder().encode(activity))
        XCTAssertEqual(decoded.savingsBytes, 250)
        XCTAssertEqual(decoded.savingsPercentage, 25)
        XCTAssertEqual(decoded.automation?.steps.first?.savedBytes, 250)
        XCTAssertEqual(decoded.automation?.dateFallback, true)
    }

    @MainActor
    func testRunNowOutputDoesNotTriggerAnotherWatchedFolder() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input")
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        try Data("copy me".utf8).write(to: input.appendingPathComponent("report.txt"))
        var copyRule = renameRule(name: "Copy")
        copyRule.actions = [AutomationAction(kind: .copy, destinationBookmark: try bookmark(output))]
        let first = try folder(input, rules: [copyRule])
        let second = try folder(output, rules: [renameRule(name: "Must not chain", prefix: "chained")])
        let suite = "OrbitConvert.AutomationWatchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([first, second]), forKey: "watchedFolders")
        let controller = WatchedFoldersController(defaults: defaults)
        defer { controller.setPaused(true) }
        for _ in 0..<100 where controller.watchedCount < 2 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(controller.watchedCount, 2)
        let preview = try await AutomationPreviewService.preview(folder: first)
        controller.runAutomation(preview, folderID: first.id)
        for _ in 0..<160 where controller.activity.isEmpty || controller.outstandingJobCount > 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(controller.activity.filter { $0.automation != nil }.count, 1)
        XCTAssertEqual(controller.activity.first?.automation?.ruleName, "Copy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("report.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("chained_report.txt").path))
    }

    func testPreviewCarriesConvertedExtensionAndKeepBothCopyForward() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        try Data("preview only".utf8).write(to: root.appendingPathComponent("photo.png"))
        var rule = AutomationRule(conditions: [AutomationCondition(value: "png")], actions: [
            AutomationAction(kind: .convert, format: "jpeg"),
            AutomationAction(kind: .rename, template: "'Converted'.{ext}")])
        let conversion = try await AutomationPreviewService.preview(folder: folder(root, rules: [rule]))
        XCTAssertTrue(try XCTUnwrap(conversion.first).summary.contains("Converted.jpg"))
        rule.actions = [AutomationAction(kind: .compress, replacement: .keepBoth),
            AutomationAction(kind: .move, destinationBookmark: try bookmark(output))]
        let compression = try await AutomationPreviewService.preview(folder: folder(root, rules: [rule]))
        XCTAssertTrue(try XCTUnwrap(compression.first).summary.contains(output.appendingPathComponent("photo-optimized.png").path))
    }

    @MainActor
    func testCollisionDoesNotDiscardAnotherApprovedInput() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.txt", "b.txt"] { try Data(name.utf8).write(to: root.appendingPathComponent(name)) }
        var rule = renameRule()
        rule.actions = [AutomationAction(kind: .rename, template: "'b'.{ext}")]
        let watched = try folder(root, rules: [rule])
        let suite = "OrbitConvert.AutomationCollision.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([watched]), forKey: "watchedFolders")
        let controller = WatchedFoldersController(defaults: defaults)
        defer { controller.remove(watched.id) }
        for _ in 0..<100 where controller.watchedCount == 0 { try await Task.sleep(for: .milliseconds(50)) }
        controller.runAutomation(try await AutomationPreviewService.preview(folder: watched), folderID: watched.id)
        for _ in 0..<200 where controller.activity.count < 2 || controller.outstandingJobCount > 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(controller.activity.count, 2)
        XCTAssertTrue(controller.activity.allSatisfy { $0.outcome == .optimized })
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("b.txt")), Data("b.txt".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("b-1.txt")), Data("a.txt".utf8))
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func bookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func folder(_ url: URL, rules: [AutomationRule]) throws -> WatchedFolder {
        var value = WatchedFolder(displayName: url.lastPathComponent, bookmarkData: try bookmark(url))
        value.rules = rules
        return value
    }

    private func renameRule(name: String = "Rename", prefix: String = "renamed") -> AutomationRule {
        AutomationRule(name: name, conditions: [AutomationCondition(field: .fileExtension, comparison: .equals, value: "txt")],
            actions: [AutomationAction(kind: .rename, template: "'\(prefix)'_{name}.{ext}")])
    }
}
