import SwiftUI
import XCTest
@testable import OrbitConvert

final class AutomationTemplateTests: XCTestCase {
    func testEveryTemplateIsValidOnceDestinationsAreChosen() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        for template in AutomationRuleTemplate.allCases {
            var rule = template.makeRule()
            XCTAssertFalse(rule.name.isEmpty)
            rule.actions = rule.actions.map { action in
                var next = action
                if [.move, .copy].contains(action.kind) { next.destinationBookmark = bookmark }
                return next
            }
            XCTAssertNoThrow(try rule.validate(), template.title)
        }
    }

    func testTemplatesNeverPickDestinationsOrReplaceOriginals() {
        for template in AutomationRuleTemplate.allCases {
            let rule = template.makeRule()
            XCTAssertTrue(rule.actions.allSatisfy { $0.destinationBookmark == nil }, template.title)
            XCTAssertTrue(rule.actions.filter { $0.kind == .compress }.allSatisfy { $0.replacement == .keepBoth }, template.title)
            if rule.actions.contains(where: { $0.kind == .move }) {
                XCTAssertThrowsError(try rule.validate(), "Move templates must ask for a destination")
            }
        }
    }

    func testEachRuleIsNewSoTemplatesCanBeAddedTwice() {
        let first = AutomationRuleTemplate.screenshots.makeRule()
        let second = AutomationRuleTemplate.screenshots.makeRule()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.actions.map(\.id), second.actions.map(\.id))
        XCTAssertNotEqual(first.conditions.map(\.id), second.conditions.map(\.id))
    }

    func testScreenshotTemplateUsesSafePaletteLikeClop() {
        let compress = AutomationRuleTemplate.screenshots.makeRule().actions.first { $0.kind == .compress }
        XCTAssertEqual(compress?.palette, .safe)
        XCTAssertNil(AutomationRuleTemplate.tidyPDFs.makeRule().actions.first { $0.kind == .compress }?.palette)
    }

    func testScreenshotTemplateMatchesScreenshotsAndRendersName() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let screenshot = folder.appendingPathComponent("Screenshot 2026-10-12 at 09.05.03.png")
        let photo = folder.appendingPathComponent("photo.png")
        for url in [screenshot, photo] { try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url) }
        let rule = AutomationRuleTemplate.screenshots.makeRule()
        XCTAssertEqual(try AutomationConditionService.firstMatch([rule], facts: .read(screenshot))?.id, rule.id)
        XCTAssertNil(try AutomationConditionService.firstMatch([rule], facts: .read(photo)))

        let rename = try XCTUnwrap(rule.actions.first { $0.kind == .rename })
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (2026, 10, 12, 9, 5, 3)
        let date = try XCTUnwrap(Calendar.current.date(from: components))
        XCTAssertEqual(try AutomationRenameTemplate(rename.template).render(originalName: "Screenshot", fileExtension: "png",
            creationDate: date, modificationDate: nil, index: 1), "Screenshot_2026-10-12_09-05-03.png")
    }

    func testSortTemplatesMatchOnlyTheirCategory() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdf = folder.appendingPathComponent("invoice.pdf"), zip = folder.appendingPathComponent("files.zip")
        for url in [pdf, zip] { try Data("x".utf8).write(to: url) }
        let rules = [AutomationRuleTemplate.sortImages, .sortPDFs, .sortArchives, .sortDocuments].map { $0.makeRule() }
        XCTAssertEqual(try AutomationConditionService.firstMatch(rules, facts: .read(pdf))?.id, rules[1].id)
        XCTAssertEqual(try AutomationConditionService.firstMatch(rules, facts: .read(zip))?.id, rules[2].id)
    }

    @MainActor
    func testEveryTemplateOpensInEditorWithoutSaving() throws {
        var saved = false
        for template in AutomationRuleTemplate.allCases {
            try render(AutomationRuleEditor(rule: template.makeRule(), onSave: { _ in saved = true }, onTest: { _ in }),
                       width: 760, height: 620, dark: template.isSorting, scrolls: true)
        }
        XCTAssertFalse(saved)
    }

    func testTemplatesMatchOnlyIntendedFiles() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        func facts(_ name: String) throws -> AutomationFileFacts {
            let url = folder.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            return try .read(url)
        }
        func matches(_ template: AutomationRuleTemplate, _ name: String) throws -> Bool {
            try AutomationConditionService.firstMatch([template.makeRule()], facts: facts(name)) != nil
        }
        XCTAssertFalse(try matches(.screenshots, "Screenshot 1.gif"), "Only PNG screenshots")
        XCTAssertFalse(try matches(.screenshots, "Screenshot_2026-10-12_09-05-03-optimized.png"), "Own outputs are skipped")
        XCTAssertTrue(try matches(.tidyPDFs, "scan.pdf"))
        XCTAssertTrue(try matches(.sortImages, "photo.jpg"))
        XCTAssertTrue(try matches(.sortDocuments, "notes.txt"))
        XCTAssertFalse(try matches(.shrinkPhotos, "animation.gif"), "Resize supports JPEG only in this template")
    }

    func testNewRulesWithoutMoveGoAboveSortRules() {
        let sort = AutomationRuleTemplate.sortImages.makeRule()
        let other = AutomationRule(name: "Existing")
        let screenshots = AutomationRuleTemplate.screenshots.makeRule()
        XCTAssertEqual(AutomationRule.inserting(screenshots, into: [other, sort]).map(\.id), [other.id, screenshots.id, sort.id])
        let secondSort = AutomationRuleTemplate.sortPDFs.makeRule()
        XCTAssertEqual(AutomationRule.inserting(secondSort, into: [other, sort]).map(\.id), [other.id, sort.id, secondSort.id])
        var edited = sort
        edited.name = "Renamed"
        XCTAssertEqual(AutomationRule.inserting(edited, into: [other, sort]).map(\.name), ["Existing", "Renamed"])
    }

    func testSortMenuTitlesDropRepeatedPrefix() {
        XCTAssertEqual(AutomationRuleTemplate.sortImages.menuTitle, "Images")
        XCTAssertEqual(AutomationRuleTemplate.screenshots.menuTitle, AutomationRuleTemplate.screenshots.title)
        XCTAssertEqual(AutomationRuleTemplate.tidyPDFs.title, "PDFs: add date and compress")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
