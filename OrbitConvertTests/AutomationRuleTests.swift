import XCTest
@testable import OrbitConvert

final class AutomationRuleTests: XCTestCase {
    func testLegacyFolderBecomesEquivalentRuleAndEmptyRulesStayEmpty() throws {
        let folder = WatchedFolder(displayName: "Old", bookmarkData: Data(), preset: .aggressive,
            supportedTypes: [.jpeg, .pdf], replacementBehavior: .moveOriginalToTrash)
        let encoded = try JSONEncoder().encode(folder)
        let decoded = try JSONDecoder().decode(WatchedFolder.self, from: encoded)
        XCTAssertEqual(decoded.effectiveRules.count, 1)
        XCTAssertEqual(decoded.effectiveRules[0].actions[0].preset, .aggressive)
        XCTAssertEqual(decoded.effectiveRules[0].actions[0].replacement, .moveOriginalToTrash)
        var empty = decoded
        empty.rules = []
        XCTAssertTrue(try JSONDecoder().decode(WatchedFolder.self, from: JSONEncoder().encode(empty)).effectiveRules.isEmpty)
    }

    func testGenericFileMatchingFirstRuleAndUnavailableValues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Invoice.txt")
        try Data("Payment received".utf8).write(to: url)
        let facts = try AutomationFileFacts.read(url, includeText: true)
        let first = AutomationRule(name: "Invoices", conditions: [
            AutomationCondition(field: .name, comparison: .contains, value: "invoice"),
            AutomationCondition(field: .text, comparison: .contains, value: "PAYMENT")],
            actions: [AutomationAction(kind: .rename)])
        XCTAssertTrue(try AutomationConditionService.matches(first, facts: facts))
        let invalid = AutomationRule(name: "Not an image", conditions: [
            AutomationCondition(field: .width, comparison: .notEquals, value: "10")], actions: [])
        XCTAssertFalse(try AutomationConditionService.matches(invalid, facts: facts))
        XCTAssertEqual(try AutomationConditionService.firstMatch([first, first.duplicated()], facts: facts)?.id, first.id)
        XCTAssertTrue(WatchFilePolicy.isEligibleFile(url, allowed: nil))
    }

    func testRenameDatesNumbersLiteralsAndExtension() throws {
        let date = Date(timeIntervalSince1970: 1791659775)
        let template = try AutomationRenameTemplate("'Photo'_yyyy-MM-dd_HH-mm-ss_{i:03}.{ext}")
        let value = try template.render(originalName: "old", fileExtension: "png", creationDate: date,
            modificationDate: nil, index: 2, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(value, "Photo_2026-10-10_19-16-15_002.png")
        XCTAssertEqual(try AutomationRenameTemplate("{name}_{i}").render(originalName: "Report",
            fileExtension: "pdf", creationDate: nil, modificationDate: nil, index: 3), "Report_3.pdf")
        XCTAssertThrowsError(try AutomationRenameTemplate("{unknown}"))
        XCTAssertThrowsError(try AutomationRenameTemplate("'unclosed"))
        XCTAssertThrowsError(try AutomationRenameTemplate("../{name}").render(originalName: "a",
            fileExtension: "txt", creationDate: nil, modificationDate: nil, index: 1))
    }
}
