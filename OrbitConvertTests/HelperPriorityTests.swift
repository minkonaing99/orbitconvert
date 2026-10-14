import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class HelperPriorityTests: XCTestCase {
    func testBackgroundJobsUseEfficiencyQoSAndOneOxipngThread() async {
        let background = await Task.detached(priority: .background) {
            (HelperPriority.isBackground, HelperPriority.helperQoS, OxipngService.threads)
        }.value
        XCTAssertTrue(background.0)
        XCTAssertEqual(background.1, .background)
        XCTAssertEqual(background.2, "1")

        let slow = await Task.detached(priority: .background) { HelperPriority.scaled(.seconds(30)) }.value
        XCTAssertEqual(slow, .seconds(120), "Efficiency cores are slower, so background deadlines stretch")

        let utility = await Task.detached(priority: .utility) { HelperPriority.helperQoS }.value
        XCTAssertEqual(utility, .background, "Utility work (rule previews, scans) never needs performance cores")

        let manual = await Task.detached(priority: .userInitiated) {
            (HelperPriority.isBackground, HelperPriority.helperQoS, OxipngService.threads)
        }.value
        XCTAssertFalse(manual.0)
        XCTAssertEqual(manual.1, .userInitiated)
        XCTAssertEqual(manual.2, "2")
        let fast = await Task.detached(priority: .userInitiated) { HelperPriority.scaled(.seconds(30)) }.value
        XCTAssertEqual(fast, .seconds(30))
    }

    func testBackgroundJobsUseCheaperOxipngLevels() async {
        let background = await Task.detached(priority: .background) {
            [OxipngService.level(for: .lossless), OxipngService.level(for: .balanced),
             OxipngService.level(for: .aggressive), OxipngService.level(for: .aggressive, quantized: true)]
        }.value
        XCTAssertEqual(background, ["1", "2", "2", "1"], "Maximum costs 2x level 2 for about 0.5% smaller files")
        let manual = await Task.detached(priority: .userInitiated) {
            [OxipngService.level(for: .lossless), OxipngService.level(for: .balanced),
             OxipngService.level(for: .aggressive), OxipngService.level(for: .aggressive, quantized: true)]
        }.value
        XCTAssertEqual(manual, ["1", "2", "4", "4"])
    }

    func testBackgroundPriorityCompressionStillWorks() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("shot.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for index in 0..<60 {
            context.setFillColor(CGColor(red: CGFloat(index % 7) / 7, green: 0.5, blue: 0.3, alpha: 1))
            context.fill(CGRect(x: (index * 37) % 400, y: (index * 53) % 300, width: 80, height: 12))
        }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)

        let outcome = try await Task.detached(priority: .background) {
            try ImageOptimizationService().optimize(file, in: folder, preset: .aggressive)
        }.value

        guard case .saved(let result) = outcome else { return XCTFail("Background compression must still optimize") }
        XCTAssertLessThan(result.outputBytes, result.originalBytes)
    }
}
