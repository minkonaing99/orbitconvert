import XCTest
@testable import OrbitConvert

@MainActor
final class LoadGateTests: XCTestCase {
    func testHotOrLowPowerGivesReason() {
        XCTAssertNil(SystemLoad(thermalState: .nominal, lowPower: false).waitReason)
        XCTAssertEqual(SystemLoad(thermalState: .fair, lowPower: false).waitReason, "Mac is warm",
                       "Pause at the first warm level, before macOS starts throttling")
        XCTAssertEqual(SystemLoad(thermalState: .serious, lowPower: false).waitReason, "Mac is hot")
        XCTAssertEqual(SystemLoad(thermalState: .critical, lowPower: true).waitReason, "Mac is hot")
        XCTAssertEqual(SystemLoad(thermalState: .nominal, lowPower: true).waitReason, "Low Power Mode")
    }

    func testSettingOffIgnoresLoad() {
        let suite = "LoadGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = LoadGate(defaults: defaults)
        gate.current = { SystemLoad(thermalState: .serious, lowPower: false) }
        XCTAssertNil(gate.reason, "Off by default under XCTest; on by default in the app")
        defaults.set(true, forKey: LoadGate.settingKey)
        XCTAssertEqual(gate.reason, "Mac is hot")
        defaults.set(false, forKey: LoadGate.settingKey)
        XCTAssertNil(gate.reason)
    }

    func testHotMacHoldsAutomationUntilItCools() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hold me".utf8).write(to: root.appendingPathComponent("note.txt"))
        var watched = WatchedFolder(displayName: "Hot", bookmarkData: try root.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
        watched.rules = [AutomationRule(conditions: [AutomationCondition(value: "txt")],
                                        actions: [AutomationAction(kind: .rename, template: "'cooled'.{ext}")])]
        let suite = "LoadGateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([watched]), forKey: "watchedFolders")
        defaults.set(true, forKey: LoadGate.settingKey)
        let controller = WatchedFoldersController(defaults: defaults)
        defer { controller.remove(watched.id) }
        var load = SystemLoad(thermalState: .serious, lowPower: false)
        controller.loadGate.current = { load }
        for _ in 0..<100 where controller.watchedCount == 0 { try await Task.sleep(for: .milliseconds(50)) }

        controller.runAutomation(try await AutomationPreviewService.preview(folder: watched), folderID: watched.id)
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(controller.activity.isEmpty, "Nothing runs while the Mac is hot")
        XCTAssertEqual(controller.outstandingJobCount, 1, "The file stays queued")
        XCTAssertEqual(controller.loadWaitReason, "Mac is hot")

        load = SystemLoad(thermalState: .nominal, lowPower: false)
        controller.loadGate.wake()
        for _ in 0..<100 where controller.activity.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("cooled.txt").path))
        XCTAssertNil(controller.loadWaitReason)
    }
}
