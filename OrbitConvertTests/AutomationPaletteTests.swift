import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class AutomationPaletteTests: XCTestCase {
    func testRulesSavedBeforePaletteDecodeAsOffAndLevelRoundTrips() throws {
        var action = AutomationAction()
        action.kind = .compress
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(action)) as? [String: Any])
        XCTAssertNil(saved["palette"])
        var rule = AutomationRule()
        rule.actions = [action]
        var folder = WatchedFolder(displayName: "Shots", bookmarkData: Data())
        folder.rules = [rule]
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode([folder])) as? [[String: Any]])
        var rules = try XCTUnwrap(legacy[0]["rules"] as? [[String: Any]])
        var actions = try XCTUnwrap(rules[0]["actions"] as? [[String: Any]])
        actions[0].removeValue(forKey: "palette")
        rules[0]["actions"] = actions
        legacy[0]["rules"] = rules
        let decoded = try JSONDecoder().decode([WatchedFolder].self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded[0].rules?[0].actions[0].palette)

        actions[0]["palette"] = "bogus"
        rules[0]["actions"] = actions
        legacy[0]["rules"] = rules
        let unknown = try JSONDecoder().decode([WatchedFolder].self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(unknown[0].rules?[0].actions[0].palette, .off, "Unknown levels must not drop watched folders")

        action.palette = .smaller
        let roundTrip = try JSONDecoder().decode(AutomationAction.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(roundTrip.palette, .smaller)
    }

    func testRuleCompressUsesPaletteOnlyWhenChosen() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writePNG(screenshotLike(), to: folder.appendingPathComponent("shot.png"))
        var action = AutomationAction()
        action.kind = .compress

        let lossless = try await AutomationMediaService().perform(action, source: source,
                                                                  expected: FileFingerprint.read(source))
        XCTAssertFalse(try chunks(lossless.url).contains("PLTE"))
        try FileManager.default.removeItem(at: lossless.url)

        action.palette = .safe
        let palette = try await AutomationMediaService().perform(action, source: source,
                                                                 expected: FileFingerprint.read(source))
        XCTAssertTrue(try chunks(palette.url).contains("PLTE"))
        XCTAssertGreaterThan(palette.savedBytes, lossless.savedBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testReplaceOriginalWithPaletteAndNoisyFallback() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writePNG(screenshotLike(), to: folder.appendingPathComponent("shot.png"))
        var action = AutomationAction()
        action.kind = .compress
        action.replacement = .replaceOriginal
        action.palette = .smaller

        let replaced = try await AutomationMediaService().perform(action, source: source,
                                                                  expected: FileFingerprint.read(source))
        XCTAssertEqual(replaced.url.standardizedFileURL, source.standardizedFileURL)
        XCTAssertTrue(try chunks(source).contains("PLTE"))

        let noisy = try writePNG(noise(), to: folder.appendingPathComponent("noise.png"))
        action.replacement = .keepBoth
        let fallback = try await AutomationMediaService().perform(action, source: noisy,
                                                                  expected: FileFingerprint.read(noisy))
        XCTAssertFalse(try chunks(fallback.url).contains("PLTE"))
    }

    private func screenshotLike() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        for index in 0..<300 {
            context.setFillColor(CGColor(red: CGFloat(index % 9) / 9, green: 0.4, blue: CGFloat(index % 4) / 4, alpha: 1))
            context.fill(CGRect(x: (index * 37) % 1200, y: (index * 53) % 800, width: 140, height: 14))
            context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.6))
            context.fillEllipse(in: CGRect(x: (index * 71) % 1200, y: (index * 29) % 800, width: 9, height: 9))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func noise() throws -> CGImage {
        let width = 256, height = 256
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 12_345
        for index in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<3 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                bytes[index + channel] = UInt8(truncatingIfNeeded: seed >> 24)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func writePNG(_ image: CGImage, to url: URL) throws -> URL {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func chunks(_ url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        var names: [String] = [], offset = 8
        while offset + 8 <= data.count {
            let length = data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            names.append(String(decoding: data[offset + 4..<offset + 8], as: UTF8.self))
            offset += 12 + length
        }
        return names
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
