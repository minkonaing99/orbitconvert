import XCTest
@testable import OrbitConvert

final class MenuStatusTests: XCTestCase {
    func testSessionSeparatesSkippedAndFailed() {
        let values = [WatchActivity(fileName: "a", outcome: .optimized, originalBytes: 100, outputBytes: 40),
                      WatchActivity(fileName: "b", outcome: .skipped, originalBytes: 80, outputBytes: 80),
                      WatchActivity(fileName: "c", outcome: .failed)]
        let stats = values.reduce(SessionStatistics()) { $0.recording($1) }
        XCTAssertEqual(stats.totalProcessed, 3)
        XCTAssertEqual(stats.successful, 1)
        XCTAssertEqual(stats.skipped, 1)
        XCTAssertEqual(stats.failed, 1)
        XCTAssertEqual(stats.bytesSaved, 60)
        XCTAssertEqual(stats.originalBytes, 100)
    }

    func testActivitySavingsIncludesBytesAndPercentage() {
        let event = WatchActivity(fileName: "photo.jpg", outcome: .optimized,
                                  originalBytes: 8_000_000, outputBytes: 2_000_000)
        XCTAssertEqual(event.savingsBytes, 6_000_000)
        XCTAssertEqual(event.savingsPercentage, 75)
        for outcome in [WatchActivityOutcome.skipped, .failed] {
            let skipped = WatchActivity(fileName: "photo.jpg", outcome: outcome,
                                        originalBytes: 8_000_000, outputBytes: 0)
            XCTAssertEqual(skipped.savingsBytes, 0)
            XCTAssertEqual(skipped.savingsPercentage, 0)
        }
        let empty = WatchActivity(fileName: "empty", outcome: .optimized)
        XCTAssertEqual(empty.savingsPercentage, 0)
        let larger = WatchActivity(fileName: "larger", outcome: .optimized,
                                    originalBytes: 10, outputBytes: 20)
        XCTAssertEqual(larger.savingsBytes, 0)
        XCTAssertEqual(larger.savingsPercentage, 0)
    }

    @MainActor func testPreviousActivityRestoresSizesAndDateWithoutChangingSession() throws {
        let suite = "ActivityHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prior = WatchActivity(fileName: "previous.jpg", outcome: .optimized,
                                  originalBytes: 8_000_000, outputBytes: 2_000_000)
        defaults.set(try JSONEncoder().encode([prior]), forKey: "watchedActivity")
        let restored = WatchedFoldersController(defaults: defaults)
        let event = try XCTUnwrap(restored.activity.first)
        XCTAssertEqual(event.id, prior.id)
        XCTAssertEqual(event.fileName, prior.fileName)
        XCTAssertEqual(event.date, prior.date)
        XCTAssertEqual(event.originalBytes, 8_000_000)
        XCTAssertEqual(event.outputBytes, 2_000_000)
        XCTAssertEqual(event.savingsPercentage, 75)
        XCTAssertEqual(restored.sessionStatistics.totalProcessed, 0)
    }

    func testZeroAndLargerOutputsHaveNoSavings() {
        let result = SessionStatistics().recording(WatchActivity(
            fileName: "empty", outcome: .optimized, originalBytes: 0, outputBytes: 10))
        XCTAssertEqual(result.bytesSaved, 0)
    }

    @MainActor func testMenuStateAndSessionDoNotUsePersistedHistory() throws {
        let suite = "MenuStatusTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = WatchedFoldersController(defaults: defaults)
        XCTAssertEqual(controller.outstandingJobCount, 0)
        XCTAssertEqual(controller.statusTitle, "")
        XCTAssertEqual(controller.sessionStatistics.totalProcessed, 0)
        controller.unavailableIDs = [UUID()]
        XCTAssertEqual(controller.watcherState, .unavailable)
        controller.activity = [WatchActivity(fileName: "old", outcome: .optimized,
                                              originalBytes: 100, outputBytes: 50)]
        XCTAssertEqual(controller.sessionStatistics.totalProcessed, 0)
        controller.setPaused(true)
        XCTAssertEqual(controller.watcherState, .paused)
        XCTAssertEqual(controller.statusSymbol, "pause.fill")
    }
}
