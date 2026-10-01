import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class WatchedFolderSafetyTests: XCTestCase {
    func testTemporaryHiddenAndSymlinkNamesAreRejected() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in [".hidden.jpg", ".DS_Store", "photo.jpg.crdownload", "photo.jpg.part",
                     "photo.jpg.download", "photo.jpg.tmp", "photo.jpg.temp", "photo.jpg.partial",
                     "photo.jpg.filepart", ".orbitconvert-job.jpg"] {
            XCTAssertFalse(WatchFilePolicy.isEligibleName(name), name)
        }
        XCTAssertTrue(WatchFilePolicy.isEligibleName("photo.jpg"))
        let link = folder.appendingPathComponent("linked.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.appendingPathComponent("target.jpg"))
        XCTAssertFalse(WatchFilePolicy.isEligibleFile(link, allowed: [.jpeg]))
    }

    func testFolderSettingsRoundTripAndDefaults() throws {
        let folder = WatchedFolder(displayName: "Photos", bookmarkData: Data([1, 2, 3]))
        XCTAssertTrue(folder.isEnabled)
        XCTAssertFalse(folder.watchSubdirectories)
        XCTAssertEqual(folder.preset, .balanced)
        XCTAssertEqual(folder.replacementBehavior, .replaceOriginal)
        XCTAssertEqual(folder.supportedTypes.contains(.heic), WatchFileType.heic.isAvailable)
        let decoded = try JSONDecoder().decode(WatchedFolder.self, from: JSONEncoder().encode(folder))
        XCTAssertEqual(decoded, folder)
    }

    func testSafeReplacementKeepsOriginalForLargerAndInvalidCandidates() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.jpg")
        let candidate = folder.appendingPathComponent("candidate.jpg")
        try Data(repeating: 1, count: 100).write(to: source)
        try Data(repeating: 2, count: 120).write(to: candidate)
        let before = try Data(contentsOf: source)
        XCTAssertThrowsError(try SafeFileReplacementService().replace(source: source, candidate: candidate,
                                                                       expected: FileFingerprint.read(source)))
        XCTAssertEqual(try Data(contentsOf: source), before)
    }

    func testSafeReplacementRejectsChangedSource() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        let candidate = folder.appendingPathComponent("candidate.txt")
        try Data(repeating: 1, count: 100).write(to: source)
        let fingerprint = try FileFingerprint.read(source)
        try Data(repeating: 3, count: 110).write(to: source)
        try Data(repeating: 2, count: 50).write(to: candidate)
        XCTAssertThrowsError(try SafeFileReplacementService().replace(source: source, candidate: candidate,
                                                                       expected: fingerprint))
        XCTAssertEqual(try Data(contentsOf: source), Data(repeating: 3, count: 110))
    }

    func testSuccessfulJPEGReplacementKeepsFilenameAndRemovesBackup() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.jpg")
        let jobs = folder.appendingPathComponent("jobs")
        try FileManager.default.createDirectory(at: jobs, withIntermediateDirectories: false)
        let context = try XCTUnwrap(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL,
                                                                        UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let item = try XCTUnwrap(FileTypeService().inspect([source]).files.first)
        let expected = try FileFingerprint.read(source)
        let outcome = try ImageOptimizationService().optimize(item, in: jobs, preset: .aggressive)
        guard case .saved(let result) = outcome else { return XCTFail("Expected smaller JPEG") }

        let replaced = try SafeFileReplacementService().replace(source: source,
                                                                 candidate: result.outputURL, expected: expected)
        XCTAssertEqual(replaced.lastPathComponent, source.lastPathComponent)
        XCTAssertLessThan(try FileFingerprint.read(source).size, expected.size)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .contains { $0.hasPrefix(".orbitconvert-backup-") })
    }

    func testStabilityWaitsForLastWrite() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.jpg")
        try Data(repeating: 1, count: 10).write(to: source)
        let task = Task.detached {
            try await FileStabilityService().waitUntilStable(source, interval: .milliseconds(30), maximumChecks: 12)
        }
        try await Task.sleep(for: .milliseconds(40))
        try Data(repeating: 2, count: 50).write(to: source)
        let stable = try await task.value
        XCTAssertEqual(stable.size, 50)
    }

    func testPDFReplacementAndPostSwapRollback() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("document.pdf")
        let candidate = folder.appendingPathComponent("candidate.pdf")
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        image.unlockFocus()
        let page = try XCTUnwrap(PDFPage(image: image))
        document.insert(page, at: 0)
        XCTAssertTrue(document.write(to: candidate))
        var padded = try Data(contentsOf: candidate)
        padded.append(Data(repeating: 0x20, count: 10_000))
        try padded.write(to: source)
        XCTAssertEqual(PDFDocument(url: source)?.pageCount, 1)
        let before = try Data(contentsOf: source)
        let expected = try FileFingerprint.read(source)

        XCTAssertThrowsError(try SafeFileReplacementService().replace(
            source: source, candidate: candidate, expected: expected,
            postReplacementCheck: { _ in false }))
        XCTAssertEqual(try Data(contentsOf: source), before)

        let output = try SafeFileReplacementService().replace(source: source,
                                                              candidate: candidate, expected: FileFingerprint.read(source))
        XCTAssertEqual(output.lastPathComponent, "document.pdf")
        XCTAssertEqual(PDFDocument(url: output)?.pageCount, 1)
        XCTAssertLessThan(try FileFingerprint.read(output).size, expected.size)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
