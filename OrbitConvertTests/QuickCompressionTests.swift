import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class QuickCompressionTests: XCTestCase {
    func testKeepBothPreservesOriginalAndExistingOutput() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try jpeg(in: folder)
        let before = try Data(contentsOf: source)
        let occupied = folder.appendingPathComponent("photo-optimized.jpg")
        try Data([1, 2, 3]).write(to: occupied)
        let results = QuickCompressionService().run([source], mode: .keepBoth, settings: .init())
        let result = try XCTUnwrap(results.first?.compression)
        XCTAssertNotEqual(result.outputURL, source)
        XCTAssertNotEqual(result.outputURL, occupied)
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(try Data(contentsOf: occupied), Data([1, 2, 3]))
        XCTAssertGreaterThan(result.savingsBytes, 0)
        XCTAssertGreaterThan(result.savingsPercentage, 0)
    }

    func testReplaceKeepsNameAndOnlySmallerValidatedImage() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try jpeg(in: folder)
        let before = try Data(contentsOf: source)
        let results = QuickCompressionService().run([source], mode: .replaceOriginal, settings: .init())
        let result = try XCTUnwrap(results.first?.compression)
        XCTAssertEqual(result.outputURL, source)
        XCTAssertLessThan(try Data(contentsOf: source).count, before.count)
        XCTAssertEqual(FileTypeService().inspect([source]).files.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["photo.jpg"])
    }

    func testChooseFolderLeavesSourceAndHandlesDuplicateNames() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("a")
        let b = folder.appendingPathComponent("b")
        let output = folder.appendingPathComponent("output")
        for url in [a, b, output] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let sources = try [jpeg(in: a), jpeg(in: b)]
        let originals = try sources.map { try Data(contentsOf: $0) }
        let results = QuickCompressionService().run(sources, mode: .chooseFolder, destination: output, settings: .init())
        let saved = results.compactMap(\.compression)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(Set(saved.map(\.outputURL)).count, 2)
        XCTAssertTrue(saved.allSatisfy { $0.outputURL.deletingLastPathComponent().path == output.path })
        XCTAssertEqual(try sources.map { try Data(contentsOf: $0) }, originals)
    }

    func testMissingDestinationInvalidInputAndPartialFailureNeverReplace() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try jpeg(in: folder)
        let before = try Data(contentsOf: source)
        let missing = QuickCompressionService().run([source], mode: .chooseFolder, settings: .init())
        XCTAssertTrue(try XCTUnwrap(missing.first).failed)
        XCTAssertEqual(try Data(contentsOf: source), before)
        let bad = folder.appendingPathComponent("missing.jpg")
        let results = QuickCompressionService().run([bad, source], mode: .keepBoth, settings: .init())
        XCTAssertTrue(results[0].failed)
        XCTAssertNotNil(results[1].compression)
        let remote = QuickCompressionService().run([URL(string: "https://example.com/photo.jpg")!], mode: .replaceOriginal, settings: .init())
        XCTAssertTrue(remote[0].failed)
    }

    func testLosslessJPEGAndSymlinksPreserveOriginal() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try jpeg(in: folder)
        let before = try Data(contentsOf: source)
        let failed = QuickCompressionService().run([source], mode: .replaceOriginal, settings: .init(preset: .lossless))
        XCTAssertTrue(failed[0].failed)
        let link = folder.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertTrue(QuickCompressionService().run([link], mode: .replaceOriginal, settings: .init())[0].failed)
        XCTAssertEqual(try Data(contentsOf: source), before)
    }

    func testRequestRoundTripAndMalformedRequests() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try jpeg(in: folder)
        let data = try QuickActionRequest.encode([source])
        XCTAssertEqual(try QuickActionRequest.decode(data), [source])
        XCTAssertThrowsError(try QuickActionRequest.encode([]))
        XCTAssertThrowsError(try QuickActionRequest.encode(Array(repeating: source, count: 101)))
        XCTAssertThrowsError(try QuickActionRequest.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try QuickActionRequest.decode(Data(repeating: 0, count: QuickActionRequest.maximumBytes + 1)))
        XCTAssertThrowsError(try QuickActionRequest.decode(Data("{\"version\":2,\"bookmarks\":[]}".utf8)))
        XCTAssertThrowsError(try QuickActionRequest.encode([URL(string: "https://example.com")!]))
    }

    func testSettingsUseSavedValuesAndSafeFallbacks() {
        let name = "QuickCompressionTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(QuickCompressionSettings(defaults: defaults).preset, .balanced)
        defaults.set("aggressive", forKey: "defaultCompressionPreset")
        defaults.set(true, forKey: "removeMetadata")
        let settings = QuickCompressionSettings(defaults: defaults)
        XCTAssertEqual(settings.preset, .aggressive)
        XCTAssertTrue(settings.removeMetadata)
        XCTAssertEqual(QuickCompressionMode(savedValue: "unknown"), .keepBoth)
        XCTAssertEqual(QuickCompressionMode(savedValue: "replaceOriginal"), .replaceOriginal)
        defaults.set("custom", forKey: "defaultCompressionPreset")
        XCTAssertEqual(QuickCompressionSettings(defaults: defaults).preset, .balanced)
    }

    func testNoReductionKeepsBytesAndCancellationSkipsAllFiles() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try jpeg(in: folder, quality: 0)
        let before = try Data(contentsOf: source)
        let results = QuickCompressionService().run([source], mode: .replaceOriginal, settings: .init())
        XCTAssertNil(results[0].compression)
        XCTAssertFalse(results[0].failed)
        XCTAssertEqual(try Data(contentsOf: source), before)
        let canceled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return QuickCompressionService().run([source], mode: .replaceOriginal, settings: .init())
        }.value
        XCTAssertNil(canceled[0].compression)
        XCTAssertTrue(canceled[0].message.contains("Canceled"))
        XCTAssertEqual(try Data(contentsOf: source), before)
    }

    func testRequestReadRejectsBadDocumentsAndDeduplicatesSelection() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try jpeg(in: folder)
        let request = folder.appendingPathComponent("selection.orbitcompress")
        try QuickActionRequest.encode([source, source]).write(to: request)
        XCTAssertEqual(try QuickActionRequest.read(request), [source])
        XCTAssertThrowsError(try QuickActionRequest.read(source))
        XCTAssertThrowsError(try QuickActionRequest.read(URL(string: "https://example.com/a.orbitcompress")!))
        let link = folder.appendingPathComponent("link.orbitcompress")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: request)
        XCTAssertThrowsError(try QuickActionRequest.read(link))
        XCTAssertThrowsError(try QuickActionRequest.bookmark(for: link))
        XCTAssertThrowsError(try QuickActionRequest.encodeBookmarks([Data()]))
        XCTAssertThrowsError(try QuickActionRequest.encodeBookmarks([Data(repeating: 0, count: 65_537)]))
        let invalidBookmark = try JSONEncoder().encode(QuickActionRequest(version: 1, bookmarks: [Data([1, 2, 3])]))
        XCTAssertThrowsError(try QuickActionRequest.decode(invalidBookmark))
        let emptyBookmark = try JSONEncoder().encode(QuickActionRequest(version: 1, bookmarks: [Data()]))
        XCTAssertThrowsError(try QuickActionRequest.decode(emptyBookmark))
        try Data(repeating: 0, count: QuickActionRequest.maximumBytes + 1).write(to: request)
        XCTAssertThrowsError(try QuickActionRequest.read(request))
    }

    func testEmbeddedFinderExtensionAcceptsOnlySupportedSelections() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/OrbitConvertQuickAction.appex")
        let bundle = try XCTUnwrap(Bundle(url: url))
        let entry = try XCTUnwrap(bundle.infoDictionary?["NSExtension"] as? [String: Any])
        XCTAssertEqual(entry["NSExtensionPointIdentifier"] as? String, "com.apple.services")
        XCTAssertEqual(entry["NSExtensionPrincipalClass"] as? String, "OrbitConvertQuickAction.ActionRequestHandler")
        let attributes = try XCTUnwrap(entry["NSExtensionAttributes"] as? [String: Any])
        let predicate = NSPredicate(format: try XCTUnwrap(attributes["NSExtensionActivationRule"] as? String))
        func accepts(_ types: [String]) -> Bool {
            predicate.evaluate(with: ["extensionItems": [["attachments": types.map { ["registeredTypeIdentifiers": [$0]] }]]])
        }
        XCTAssertTrue(accepts(["public.jpeg", "public.png", "public.heic"]))
        XCTAssertFalse(accepts(["public.pdf"]))
        XCTAssertFalse(accepts(["public.jpeg", "public.plain-text"]))
        XCTAssertFalse(accepts([]))
        XCTAssertFalse(accepts(Array(repeating: "public.jpeg", count: 101)))
        XCTAssertNotNil(Bundle.main.infoDictionary?["CFBundleDocumentTypes"])
    }

    private func directory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func jpeg(in folder: URL, quality: Double = 1) throws -> URL {
        let url = folder.appendingPathComponent("photo.jpg")
        let context = try XCTUnwrap(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()),
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
