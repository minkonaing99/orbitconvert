import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class ClipboardPaletteTests: XCTestCase {
    func testClipboardScreenshotUsesPaletteOnlyWhenChosen() throws {
        let data = try screenshotPNG()
        let item = ClipboardItem(generation: 1, data: data, fileURL: nil, typeIdentifier: UTType.png.identifier)

        let lossless = try XCTUnwrap(ClipboardOptimizationService().optimize(item, preset: .balanced))
        let palette = try XCTUnwrap(ClipboardOptimizationService().optimize(item, preset: .balanced, palette: .safe))

        XCTAssertFalse(chunks(lossless.data).contains("PLTE"))
        XCTAssertTrue(chunks(palette.data).contains("PLTE"))
        XCTAssertLessThan(palette.data.count, lossless.data.count)

        let strict = try XCTUnwrap(ClipboardOptimizationService().optimize(item, preset: .lossless, palette: .safe))
        XCTAssertFalse(chunks(strict.data).contains("PLTE"), "Lossless never uses the lossy palette")
    }

    @MainActor
    func testMonitorStoresLevelAndPassesItToOptimizer() async throws {
        let suite = "ClipboardPaletteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let seen = SeenSettings()
        let monitor = ClipboardMonitorService(defaults: defaults, pasteboard: board) { _, settings, _ in
            seen.value = settings
            return nil
        }
        XCTAssertEqual(monitor.palette, .off)
        monitor.palette = .smaller
        XCTAssertEqual(defaults.string(forKey: "clipboardPalette"), "smaller")
        XCTAssertEqual(ClipboardMonitorService(defaults: defaults, pasteboard: board).palette, .smaller)

        let data = try screenshotPNG()
        board.setData(data, forType: .png)
        let item = ClipboardItem(generation: board.changeCount, data: data, fileURL: nil, typeIdentifier: UTType.png.identifier)
        _ = await monitor.process(item)

        XCTAssertEqual(seen.value?.palette, .smaller)
        XCTAssertEqual(seen.value?.preset, monitor.preset)
    }

    private final class SeenSettings: @unchecked Sendable {
        var value: ClipboardCompression?
    }

    private func screenshotPNG() throws -> Data {
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
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func chunks(_ data: Data) -> [String] {
        var names: [String] = [], offset = 8
        while offset + 8 <= data.count {
            let length = data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            names.append(String(decoding: data[offset + 4..<offset + 8], as: UTF8.self))
            offset += 12 + length
        }
        return names
    }
}
