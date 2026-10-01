import AppKit
import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import OrbitConvert

@MainActor final class ClipboardTests: XCTestCase {
    func testNewGenerationNeverWritten() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("new user content", forType: .string)
        let writer = ClipboardWriterService(pasteboard: board)
        let result = writer.write(data: try fixture(.png), type: .png, expectedGeneration: board.changeCount - 1)
        XCTAssertFalse(result)
        XCTAssertEqual(board.string(forType: .string), "new user content")
    }
    func testFingerprintRegistryIsBoundedAndRecognizesCopies() {
        var registry = ClipboardFingerprintRegistry()
        let data = Data([1, 2, 3])
        registry.insert(ClipboardFingerprintRegistry.fingerprint(data))
        XCTAssertTrue(registry.contains(ClipboardFingerprintRegistry.fingerprint(data)))
        for index in 0..<300 { registry.insert(String(index)) }
        XCTAssertLessThanOrEqual(registry.count, 128)
    }
    func testUnsupportedAndConcealedTypesIgnored() {
        XCTAssertNil(ClipboardItem.preferredType([.string]))
        XCTAssertNil(ClipboardItem.preferredType([.png, .init("org.nspasteboard.ConcealedType")]))
        XCTAssertEqual(ClipboardItem.preferredType([.tiff, .png]), .png)
    }
    func testOwnWriteCarriesMarkerAndGeneration() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let writer = ClipboardWriterService(pasteboard: board)
        XCTAssertTrue(writer.write(data: try fixture(.png), type: .png, expectedGeneration: board.changeCount))
        XCTAssertEqual(writer.lastWrittenGeneration, board.changeCount)
        XCTAssertNil(ClipboardItem.preferredType(board.types ?? []))
    }

    func testRawPNGOptimizationPreservesAlphaAndCleansTemporaryFiles() throws {
        let bytes = try fixture(.png)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try XCTUnwrap(ClipboardOptimizationService().optimize(
            ClipboardItem(generation: 1, data: bytes, fileURL: nil, typeIdentifier: UTType.png.identifier),
            preset: .balanced, workingRoot: root))
        XCTAssertLessThan(result.data.count, bytes.count)
        XCTAssertEqual(try pixels(bytes), try pixels(result.data))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        XCTAssertEqual(result.width, 256)
        XCTAssertNotNil(result.percentage)
    }

    func testTIFFConvertsToPNGAndJPEGUsesExistingOptimizer() throws {
        for type in [UTType.tiff, .jpeg] {
            let bytes = try fixture(type)
            let result = try ClipboardOptimizationService().optimize(
                ClipboardItem(generation: 1, data: bytes, fileURL: nil, typeIdentifier: type.identifier), preset: .balanced)
            if type == .tiff {
                let output = try XCTUnwrap(result)
                XCTAssertEqual(output.typeIdentifier, UTType.png.identifier)
                XCTAssertEqual(try pixels(bytes), try pixels(output.data))
            }
            if let result { XCTAssertLessThan(result.data.count, bytes.count) }
        }
    }

    func testCopiedFileRemainsUnchangedAndInvalidInputCleansUp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("photo.png")
        let bytes = try fixture(.png)
        try bytes.write(to: source)
        let jobs = root.appendingPathComponent("jobs")
        let result = try ClipboardOptimizationService().optimize(
            ClipboardItem(generation: 1, data: nil, fileURL: source, typeIdentifier: UTType.png.identifier),
            preset: .balanced, workingRoot: jobs)
        XCTAssertTrue(try XCTUnwrap(result).fileBacked)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertThrowsError(try ClipboardOptimizationService().optimize(
            ClipboardItem(generation: 1, data: Data([0, 1]), fileURL: nil, typeIdentifier: UTType.png.identifier),
            preset: .balanced, workingRoot: jobs))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: jobs.path).isEmpty)
    }

    func testIgnoredAppAndUnsupportedClipboardDoNotQueue() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuite") ?? "") }
        let monitor = ClipboardMonitorService(defaults: defaults, pasteboard: board)
        monitor.ignoredApps = ["example.editor"]
        var calls = 0
        monitor.start(submit: { _ in calls += 1 }, cancelPending: {})
        defer { monitor.stop() }
        board.setData(try fixture(.png), forType: .png)
        monitor.checkClipboard(frontmostBundleID: "example.editor")
        XCTAssertEqual(calls, 0)
        board.clearContents(); board.setString("password", forType: .string)
        monitor.checkClipboard(frontmostBundleID: nil)
        XCTAssertEqual(calls, 0)
        board.clearContents(); board.setData(try fixture(.png), forType: .png)
        monitor.checkClipboard(frontmostBundleID: "example.other")
        XCTAssertEqual(calls, 1)
    }

    func testRapidCopyPreservesNewestUserContent() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let data = try fixture(.png)
        let output = fakeResult(data)
        let started = expectation(description: "Optimization started")
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuite") ?? "") }
        let monitor = ClipboardMonitorService(defaults: defaults, pasteboard: board) { _, _, _ in
            started.fulfill()
            Thread.sleep(forTimeInterval: 0.15)
            return output
        }
        monitor.showResults = false
        board.setData(data, forType: .png)
        let item = ClipboardItem(generation: board.changeCount, data: data, fileURL: nil, typeIdentifier: UTType.png.identifier)
        let job = Task { await monitor.process(item) }
        await fulfillment(of: [started], timeout: 2)
        board.clearContents(); board.setString("newer copy C", forType: .string)
        let result = await job.value
        XCTAssertEqual(result?.outcome, .skipped)
        XCTAssertEqual(board.string(forType: .string), "newer copy C")
    }

    func testFailureAndNoReductionLeaveClipboardUntouched() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let bytes = try fixture(.png)
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuite") ?? "") }
        for fails in [false, true] {
            let monitor = ClipboardMonitorService(defaults: defaults, pasteboard: board) { _, _, _ in
                if fails { throw OptimizationError.cannotEncode }
                return nil
            }
            board.clearContents(); board.setData(bytes, forType: .png)
            let generation = board.changeCount
            let result = await monitor.process(ClipboardItem(generation: generation, data: bytes,
                fileURL: nil, typeIdentifier: UTType.png.identifier))
            XCTAssertEqual(result?.outcome, fails ? .failed : .skipped)
            XCTAssertEqual(board.changeCount, generation)
            XCTAssertEqual(board.data(forType: .png), bytes)
        }
    }

    func testSharedQueueProcessesClipboardWhileFoldersPaused() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuite") ?? "") }
        let controller = WatchedFoldersController(defaults: defaults)
        controller.setPaused(true)
        let done = expectation(description: "Clipboard processed independently")
        controller.enqueueClipboard {
            done.fulfill()
            return WatchActivity(fileName: "Clipboard image", outcome: .optimized, originalBytes: 100, outputBytes: 20)
        }
        XCTAssertEqual(controller.clipboardJobCount, 1)
        XCTAssertEqual(controller.statusTitle, "1")
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(controller.sessionStatistics.bytesSaved, 80)
        XCTAssertEqual(controller.outstandingJobCount, 0)
    }

    func testFileExportsCanBeRecopiedAndAreCleanedAfterClipboardChanges() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let writer = ClipboardWriterService(pasteboard: board)
        let result = fakeResult(try fixture(.png), fileBacked: true)
        var exported: URL?
        for _ in 0..<40 {
            let item = try await writer.item(for: result)
            let url = try XCTUnwrap(item as? NSURL) as URL
            if let exported { XCTAssertEqual(exported, url) }
            exported = url
            XCTAssertTrue(writer.write([item], expectedGeneration: board.changeCount))
            let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            XCTAssertEqual(urls?.first, url)
            XCTAssertEqual(try Data(contentsOf: url), result.data)
        }
        board.clearContents(); board.setString("new content", forType: .string)
        writer.cleanupExports()
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(exported).path))
    }

    func testDisabledMonitorDoesNotAdmitNewCopies() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuite") ?? "") }
        let monitor = ClipboardMonitorService(defaults: defaults, pasteboard: board)
        var calls = 0
        monitor.start(submit: { _ in calls += 1 }, cancelPending: {})
        defer { monitor.stop() }
        monitor.enabled = false
        board.setData(try fixture(.png), forType: .png)
        monitor.checkClipboard(frontmostBundleID: nil)
        XCTAssertEqual(calls, 0)
        monitor.enabled = true
        monitor.checkClipboard(frontmostBundleID: nil)
        XCTAssertEqual(calls, 0)
        board.clearContents(); board.setData(try fixture(.png), forType: .png)
        monitor.checkClipboard(frontmostBundleID: nil)
        XCTAssertEqual(calls, 1)
    }

    func testOptimizedFingerprintPreventsGenerationLoss() throws {
        let bytes = try fixture(.png)
        let result = try XCTUnwrap(ClipboardOptimizationService().optimize(
            ClipboardItem(generation: 1, data: bytes, fileURL: nil, typeIdentifier: UTType.png.identifier), preset: .balanced))
        let outputHash = result.outputFingerprint
        XCTAssertNil(try ClipboardOptimizationService().optimize(
            ClipboardItem(generation: 2, data: result.data, fileURL: nil, typeIdentifier: result.typeIdentifier),
            preset: .balanced, shouldSkip: { $0 == outputHash }))
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "ClipboardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set(name, forKey: "testSuite")
        return defaults
    }
    private func fakeResult(_ data: Data, fileBacked: Bool = false) -> ClipboardOptimizationResult {
        ClipboardOptimizationResult(data: data, typeIdentifier: UTType.png.identifier,
            originalBytes: Int64(data.count * 2), width: 256, height: 256, thumbnailData: Data(), duration: 0,
            sourceFingerprint: "source", outputFingerprint: ClipboardFingerprintRegistry.fingerprint(data), fileBacked: fileBacked)
    }
    private func fixture(_ type: UTType) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.8, alpha: type == .jpeg ? 1 : 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    private func pixels(_ data: Data) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
    }

}
