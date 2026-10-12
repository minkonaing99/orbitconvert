import XCTest
@testable import OrbitConvert

final class LifetimeSavingsTests: XCTestCase {
    func testAddingCountsOnlyPositiveSavingsAndReturnsNewValue() {
        let start = LifetimeSavings(bytes: 100, files: 1)
        XCTAssertEqual(start.adding(50), LifetimeSavings(bytes: 150, files: 2))
        XCTAssertEqual(start.adding(0), start)
        XCTAssertEqual(start.adding(-20), start)
        XCTAssertEqual(start, LifetimeSavings(bytes: 100, files: 1))
    }

    func testSummaryUsesFileUnitsAndPluralization() {
        XCTAssertEqual(LifetimeSavings(bytes: 1_500_000, files: 2).summary, "Total saved: 1.5 MB across 2 files")
        XCTAssertEqual(LifetimeSavings(bytes: 2_000, files: 1).summary, "Total saved: 2 KB across 1 file")
    }

    func testAddingClampsInsteadOfOverflowing() {
        let nearlyFull = LifetimeSavings(bytes: .max - 10, files: .max)
        XCTAssertEqual(nearlyFull.adding(100), LifetimeSavings(bytes: .max, files: .max))
    }

    func testLoadSeedsFromHistoryOnlyOnce() throws {
        let (defaults, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let history = [
            WatchActivity(fileName: "a.jpg", outcome: .optimized, originalBytes: 2_000, outputBytes: 1_200),
            WatchActivity(fileName: "b.png", outcome: .skipped, originalBytes: 500, outputBytes: 500),
            WatchActivity(fileName: "c.pdf", outcome: .failed, message: "Failed")]
        XCTAssertEqual(LifetimeSavings.load(from: defaults, seedingFrom: history), LifetimeSavings(bytes: 800, files: 1))
        XCTAssertEqual(LifetimeSavings.load(from: defaults, seedingFrom: history + history),
                       LifetimeSavings(bytes: 800, files: 1), "Seeding must not repeat")
    }

    @MainActor
    func testManualRecordingPersistsAndUpdatesRunningController() async throws {
        let (defaults, cleanup) = try isolatedDefaults()
        defer { cleanup() }
        let controller = WatchedFoldersController(defaults: defaults)
        XCTAssertEqual(controller.lifetimeSavings, LifetimeSavings())
        let saved = CompressionResult(originalURL: URL(fileURLWithPath: "/tmp/a.jpg"),
            outputURL: URL(fileURLWithPath: "/tmp/a-1.jpg"), originalBytes: 3_000, outputBytes: 1_000)
        let larger = CompressionResult(originalURL: URL(fileURLWithPath: "/tmp/b.jpg"),
            outputURL: URL(fileURLWithPath: "/tmp/b-1.jpg"), originalBytes: 100, outputBytes: 200)
        LifetimeSavings.record([saved, larger], in: defaults)
        for _ in 0..<40 where controller.lifetimeSavings.bytes == 0 { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(controller.lifetimeSavings, LifetimeSavings(bytes: 2_000, files: 1))
        XCTAssertEqual(WatchedFoldersController(defaults: defaults).lifetimeSavings, LifetimeSavings(bytes: 2_000, files: 1))

        controller.resetLifetimeSavings()
        XCTAssertEqual(controller.lifetimeSavings, LifetimeSavings())
        XCTAssertEqual(LifetimeSavings.load(from: defaults, seedingFrom: []), LifetimeSavings())
    }

    private func isolatedDefaults() throws -> (UserDefaults, () -> Void) {
        let suite = "OrbitConvert.LifetimeSavings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }
}
