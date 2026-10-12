import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class JPEGQualityEstimatorTests: XCTestCase {
    private static let standardLuminance = [
        16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55,
        14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
        18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
        49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99
    ]

    func testEstimatesIJGQualityFromLuminanceTable() throws {
        for quality in [50, 70, 85, 95] {
            let estimate = try XCTUnwrap(JPEGQualityEstimator.estimate(jpeg(table: ijgTable(quality))))
            XCTAssertEqual(Double(estimate), Double(quality), accuracy: 2, "quality \(quality)")
        }
    }

    func testReadsSixteenBitTablesAndSkipsChromaTable() throws {
        let chroma = Array(repeating: 99, count: 64)
        let data = jpeg(tables: [(1, chroma, false), (0, ijgTable(70), true)])
        XCTAssertEqual(Double(try XCTUnwrap(JPEGQualityEstimator.estimate(data))), 70, accuracy: 2)
    }

    func testUsesTableNamedByFirstFrameComponent() throws {
        let chroma = Array(repeating: 99, count: 64)
        let sof: [UInt8] = [0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x10, 0x00, 0x10, 0x01, 0x01, 0x11, 0x01]
        let data = jpeg(tables: [(0, chroma, false), (1, ijgTable(70), false)], frame: sof)
        XCTAssertEqual(Double(try XCTUnwrap(JPEGQualityEstimator.estimate(data))), 70, accuracy: 2)
    }

    func testRejectsCorruptOrMissingTables() {
        XCTAssertNil(JPEGQualityEstimator.estimate(Data()))
        XCTAssertNil(JPEGQualityEstimator.estimate(Data([0x89, 0x50, 0x4E, 0x47])))
        XCTAssertNil(JPEGQualityEstimator.estimate(Data([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02])))
        let truncated = jpeg(table: ijgTable(80)).prefix(30)
        XCTAssertNil(JPEGQualityEstimator.estimate(Data(truncated)))
        XCTAssertNil(JPEGQualityEstimator.estimate(jpeg(table: Array(repeating: 0, count: 64))))
        var badLength = jpeg(table: ijgTable(80))
        badLength[4] = 0xFF
        XCTAssertNil(JPEGQualityEstimator.estimate(badLength))
    }

    func testImageIOEquivalentRisesWithQuality() throws {
        let low = try XCTUnwrap(JPEGQualityEstimator.imageIOEquivalent(0.3))
        let balanced = try XCTUnwrap(JPEGQualityEstimator.imageIOEquivalent(0.85))
        let best = try XCTUnwrap(JPEGQualityEstimator.imageIOEquivalent(1.0))
        XCTAssertLessThan(low, balanced)
        XCTAssertLessThanOrEqual(balanced, best)
        XCTAssertNil(JPEGQualityEstimator.imageIOEquivalent(.nan))
    }

    func testEstimatesImageIOFileOnDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("q.jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.jpeg.identifier as CFString, 1, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()),
                                   [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        XCTAssertEqual(JPEGQualityEstimator.estimate(contentsOf: url), JPEGQualityEstimator.imageIOEquivalent(0.5))
        XCTAssertNil(JPEGQualityEstimator.estimate(contentsOf: folder.appendingPathComponent("missing.jpg")))
    }

    private func ijgTable(_ quality: Int) -> [Int] {
        let scale = quality < 50 ? 5000 / quality : 200 - quality * 2
        return Self.standardLuminance.map { min(255, max(1, ($0 * scale + 50) / 100)) }
    }

    private func jpeg(table: [Int]) -> Data {
        jpeg(tables: [(0, table, false)])
    }

    private func jpeg(tables: [(id: UInt8, values: [Int], sixteenBit: Bool)], frame: [UInt8] = []) -> Data {
        var body: [UInt8] = []
        for table in tables {
            body.append((table.sixteenBit ? 0x10 : 0) | table.id)
            for value in table.values {
                if table.sixteenBit { body.append(UInt8(value >> 8)) }
                body.append(UInt8(value & 0xFF))
            }
        }
        let length = body.count + 2
        let app0: [UInt8] = [0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00]
        return Data([0xFF, 0xD8] + app0 + [0xFF, 0xDB, UInt8(length >> 8), UInt8(length & 0xFF)] + body
                    + frame + [0xFF, 0xDA, 0x00, 0x02])
    }
}
