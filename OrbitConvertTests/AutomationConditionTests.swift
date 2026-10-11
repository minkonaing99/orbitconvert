import XCTest
@testable import OrbitConvert

final class AutomationConditionTests: XCTestCase {
    private func facts(width: Int? = 1920, text: String? = "Invoice paid", tags: [String] = ["Work", "Blue"]) -> AutomationFileFacts {
        AutomationFileFacts(url: URL(fileURLWithPath: "/tmp/Photo.PNG"),
            fingerprint: FileFingerprint(device: 1, inode: 1, size: 2_000_000,
                modifiedSeconds: 0, modifiedNanoseconds: 0, changedSeconds: 0, changedNanoseconds: 0),
            creationDate: AutomationConditionService.date("2026-10-10"),
            modificationDate: AutomationConditionService.date("2026-10-11"),
            typeIdentifier: "public.png", category: "Image", width: width, height: 1080,
            tags: tags, text: text, textIssue: nil)
    }

    func testTextFieldsAndComparisonsIgnoreCase() throws {
        let cases: [(AutomationField, AutomationComparison, String, Bool)] = [
            (.name, .equals, "photo.png", true), (.name, .notEquals, "photo.png", false),
            (.name, .contains, "OTO", true), (.name, .notContains, "raw", true),
            (.name, .startsWith, "pho", true), (.name, .endsWith, ".PNG", true),
            (.fileExtension, .equals, "png", true), (.category, .equals, "IMAGE", true),
            (.tags, .equals, "work", true), (.tags, .notEquals, "work", false),
            (.tags, .notContains, "lu", false), (.tags, .notContains, "red", true),
            (.text, .contains, "PAID", true), (.text, .endsWith, "paid", true),
            (.typeIdentifier, .equals, "public.image", true),
            (.typeIdentifier, .notEquals, "com.adobe.pdf", true)
        ]
        for (field, comparison, value, expected) in cases {
            XCTAssertEqual(try AutomationConditionService.matches(
                AutomationCondition(field: field, comparison: comparison, value: value), facts: facts()),
                expected, "\(field) \(comparison) \(value)")
        }
        XCTAssertTrue(try AutomationConditionService.matches(
            AutomationCondition(field: .tags, comparison: .notContains, value: "work"), facts: facts(tags: [])))
        XCTAssertFalse(try AutomationConditionService.matches(
            AutomationCondition(field: .text, comparison: .notContains, value: "paid"), facts: facts(text: nil)))
    }

    func testNumericDatesAndUnavailableDimensions() throws {
        let cases: [(AutomationField, AutomationComparison, String, Bool)] = [
            (.size, .equals, "2", true), (.size, .greater, "1.99", true),
            (.size, .less, "2", false), (.width, .notEquals, "100", true),
            (.height, .less, "1081", true), (.height, .equals, "1080", true),
            (.created, .equals, "2026-10-10", true), (.modified, .greater, "2026-10-10", true),
            (.modified, .less, "2026-10-12", true), (.created, .notEquals, "2026-10-10", false),
            (.size, .equals, "nan", false), (.created, .equals, "bad", false)
        ]
        for (field, comparison, value, expected) in cases {
            XCTAssertEqual(try AutomationConditionService.matches(
                AutomationCondition(field: field, comparison: comparison, value: value), facts: facts()), expected)
        }
        XCTAssertFalse(try AutomationConditionService.matches(
            AutomationCondition(field: .width, comparison: .notEquals, value: "0"), facts: facts(width: nil)))
        for invalid in ["2026-02-30", "2026-2-01", "2026-13-01", "not a date"] {
            XCTAssertNil(AutomationConditionService.date(invalid))
        }
        XCTAssertNotNil(AutomationConditionService.date("2024-02-29"))
    }

    func testRulePriorityDisabledRulesAndSubfolderScope() throws {
        let yes = AutomationCondition(field: .category, value: "Image")
        let no = AutomationCondition(field: .category, value: "Video")
        let disabled = AutomationRule(name: "Disabled", isEnabled: false, conditions: [yes])
        let local = AutomationRule(name: "Local", conditions: [yes])
        let recursive = AutomationRule(name: "Recursive", includeSubfolders: true, matchAll: false, conditions: [yes, no])
        XCTAssertEqual(try AutomationConditionService.firstMatch([disabled, local, recursive], facts: facts())?.id, local.id)
        XCTAssertEqual(try AutomationConditionService.firstMatch([disabled, local, recursive], facts: facts(), isSubfolder: true)?.id, recursive.id)
        XCTAssertFalse(try AutomationConditionService.matches(AutomationRule(conditions: [yes, no]), facts: facts()))
        XCTAssertFalse(try AutomationConditionService.matches(AutomationRule(conditions: []), facts: facts()))
        XCTAssertNil(try AutomationConditionService.firstMatch([disabled], facts: facts()))
    }

    func testValidationRejectsInvalidInputsAndAcceptsBoundaries() throws {
        XCTAssertNoThrow(try AutomationRule().validate())
        let invalidRules = [AutomationRule(name: " "), AutomationRule(name: String(repeating: "x", count: 121)),
            AutomationRule(conditions: []), AutomationRule(actions: []),
            AutomationRule(conditions: Array(repeating: AutomationCondition(), count: 33)),
            AutomationRule(actions: Array(repeating: AutomationAction(), count: 17))]
        for rule in invalidRules { XCTAssertThrowsError(try rule.validate()) }
        for condition in [AutomationCondition(value: ""), AutomationCondition(field: .width, comparison: .contains, value: "1"),
                          AutomationCondition(field: .size, value: "-1"), AutomationCondition(field: .size, value: "inf"),
                          AutomationCondition(field: .created, value: "2026-02-30")] {
            XCTAssertThrowsError(try AutomationRule(conditions: [condition]).validate())
        }
        for action in [AutomationAction(kind: .move), AutomationAction(kind: .copy),
                       AutomationAction(preset: .custom), AutomationAction(format: "exe"),
                       AutomationAction(width: 0), AutomationAction(height: 100_001),
                       AutomationAction(quality: .nan), AutomationAction(quality: 1.01)] {
            XCTAssertThrowsError(try AutomationRule(actions: [action]).validate())
        }
        XCTAssertNoThrow(try AutomationRule(actions: [AutomationAction(width: 1, height: 100_000, quality: 0)]).validate())
    }
}
