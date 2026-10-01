import Foundation
import CoreServices
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

@MainActor
final class FolderWatchServiceTests: XCTestCase {
    func testFSEventsReportsNewFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let event = expectation(description: "Folder change delivered")
        var delivered = false
        let watcher = try FolderWatchService(folder: folder) { _, _, _ in
            if !delivered { delivered = true; event.fulfill() }
        }
        defer { watcher.stop() }
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("new-file.jpg"))
        await fulfillment(of: [event], timeout: 5)
    }

    func testFSEventsReplaysFileCreatedDuringStartupScan() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sinceID = FSEventsGetCurrentEventId()
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("during-scan.jpg"))
        let event = expectation(description: "Startup event replayed")
        var delivered = false
        let watcher = try FolderWatchService(folder: folder, since: sinceID) { url, flags, _ in
            if url.lastPathComponent == "during-scan.jpg",
               flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0,
               !delivered {
                delivered = true
                event.fulfill()
            }
        }
        defer { watcher.stop() }
        await fulfillment(of: [event], timeout: 5)
    }

    func testDisabledFolderSettingsPersistWithoutStartingWatch() throws {
        let suite = "OrbitConvertTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var folder = WatchedFolder(displayName: "Photos", bookmarkData: Data([1, 2, 3]))
        folder.isEnabled = false
        defaults.set(try JSONEncoder().encode([folder]), forKey: "watchedFolders")
        let controller = WatchedFoldersController(defaults: defaults)
        XCTAssertEqual(controller.folders.count, 1)
        XCTAssertEqual(controller.watchedCount, 0)
        controller.setPaused(true)
        XCTAssertTrue(WatchedFoldersController(defaults: defaults).paused)
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: invalid)
        defer { try? FileManager.default.removeItem(at: invalid) }
        XCTAssertThrowsError(try controller.relink(folder.id, to: invalid))
        controller.remove(folder.id)
        XCTAssertTrue(WatchedFoldersController(defaults: defaults).folders.isEmpty)
    }

    func testExistingFilesAreNotOptimizedAndNewFilesAreQueued() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("existing.jpg")
        try makeJPEG(existing)
        let suite = "OrbitConvertTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = WatchedFoldersController(defaults: defaults)
        do { try controller.add([root], optimizeExisting: false) }
        catch { throw XCTSkip("Security-scoped bookmarks require a signed test host: \(error)") }
        for _ in 0..<30 where controller.watchedCount == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard controller.watchedCount == 1 else {
            throw XCTSkip("Security-scoped folder access requires a signed test host")
        }
        XCTAssertTrue(controller.activity.isEmpty)
        let incoming = root.appendingPathComponent("incoming.jpg")
        try FileManager.default.copyItem(at: existing, to: incoming)
        for _ in 0..<80 where controller.activity.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(controller.outstandingJobCount, 0)
        XCTAssertEqual(controller.sessionStatistics.totalProcessed, 1)
        XCTAssertEqual(controller.sessionStatistics.successful + controller.sessionStatistics.skipped +
                       controller.sessionStatistics.failed, 1)
        XCTAssertEqual(controller.activity.first?.fileName, "incoming.jpg")
        XCTAssertFalse(controller.activity.contains { $0.fileName == "existing.jpg" })
        controller.setPaused(true)
    }

    func testMenuCountsAndPausePreserveAcceptedQueue() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "MenuQueueTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = WatchedFoldersController(defaults: defaults)
        try controller.add([root], optimizeExisting: false)
        for _ in 0..<40 where controller.watchedCount == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        defer { for folder in controller.folders { controller.remove(folder.id) } }
        for index in 0..<3 { try makeJPEG(root.appendingPathComponent("photo-\(index).jpg")) }
        for _ in 0..<40 where controller.outstandingJobCount < 3 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(controller.outstandingJobCount, 3)
        XCTAssertEqual(controller.statusTitle, "3")
        XCTAssertEqual(controller.activeJobs.count + controller.queuedJobs.count, 3)
        controller.setPaused(true)
        XCTAssertEqual(controller.statusTitle, "")
        for _ in 0..<80 where !controller.activeJobs.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(controller.queuedJobs.count, 2)
        XCTAssertEqual(controller.sessionStatistics.totalProcessed, 1)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.queuedJobs.count, 2)
        controller.setPaused(false)
        for _ in 0..<100 where controller.outstandingJobCount > 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(controller.outstandingJobCount, 0)
        XCTAssertEqual(controller.statusTitle, "")
        XCTAssertEqual(controller.sessionStatistics.totalProcessed, 3)
    }

    func testKeepBothDoesNotRequeueItsOwnOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "OrbitConvertTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = WatchedFoldersController(defaults: defaults)
        try controller.add([root], optimizeExisting: false)
        var settings = try XCTUnwrap(controller.folders.first)
        settings.replacementBehavior = .keepBoth
        controller.update(settings)
        for _ in 0..<30 where controller.watchedCount == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(controller.watchedCount, 1)
        let incoming = root.appendingPathComponent("incoming.jpg")
        try makeJPEG(incoming)
        for _ in 0..<80 where controller.activity.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(controller.activity.first?.outcome, .optimized)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("incoming-optimized.jpg").path))
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(controller.activity.count, 1)
        controller.setPaused(true)
    }

    func testOptimizeExistingChoiceQueuesBaselineFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeJPEG(root.appendingPathComponent("existing.jpg"))
        let suite = "OrbitConvertTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = WatchedFoldersController(defaults: defaults)
        try controller.add([root], optimizeExisting: true)
        for _ in 0..<80 where controller.activity.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(controller.activity.first?.fileName, "existing.jpg")
        controller.setPaused(true)
    }

    func testSubfolderWatchingSkipsPackageContents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "OrbitConvertTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = WatchedFoldersController(defaults: defaults)
        try controller.add([root], optimizeExisting: false)
        var settings = try XCTUnwrap(controller.folders.first)
        settings.watchSubdirectories = true
        controller.update(settings)
        for _ in 0..<30 where controller.watchedCount == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(controller.watchedCount, 1)
        let package = root.appendingPathComponent("Example.app/Contents/Resources")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let bundled = package.appendingPathComponent("icon.jpg")
        try makeJPEG(bundled)
        let before = try Data(contentsOf: bundled)
        try await Task.sleep(for: .seconds(3))
        XCTAssertTrue(controller.activity.isEmpty)
        XCTAssertEqual(try Data(contentsOf: bundled), before)
        controller.setPaused(true)
    }

    private func makeJPEG(_ url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100,
                                             bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
                                                                        UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
