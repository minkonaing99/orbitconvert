import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Estimates JPEG quality on the IJG 1-100 scale from the luminance quantization table, without decoding pixels.
// ImageIO quality values use different tables, so compare against `imageIOEquivalent`, not the raw preset.
nonisolated enum JPEGQualityEstimator {
    private static let standardLuminanceSum = 3688
    private static let maxHeaderBytes = 4_000_000

    static func estimate(contentsOf url: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxHeaderBytes) else { return nil }
        return estimate(data)
    }

    static func estimate(_ data: Data) -> Int? {
        guard let table = luminanceTable(in: [UInt8](data)), !table.contains(0) else { return nil }
        let scale = Double(table.reduce(0, +)) * 100 / Double(standardLuminanceSum)
        let quality = scale <= 100 ? (200 - scale) / 2 : 5000 / scale
        return min(100, max(1, Int(quality.rounded())))
    }

    /// IJG-scale quality of the tables ImageIO writes for `quality`, measured by encoding a tiny image.
    static func imageIOEquivalent(_ quality: Double) -> Int? {
        guard quality.isFinite, (0...1).contains(quality),
              let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return estimate(data as Data)
    }

    // Walks marker segments from SOI to SOS. The luminance table is the one the first frame component
    // (SOF0-SOF2) names; table 0 when no frame header precedes the scan.
    private static func luminanceTable(in bytes: [UInt8]) -> [Int]? {
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var tables: [UInt8: [Int]] = [:]
        var luminanceID: UInt8?
        var index = 2
        while index + 4 <= bytes.count, bytes[index] == 0xFF {
            let marker = bytes[index + 1]
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let end = index + 2 + length
            if marker == 0xDA { return tables[luminanceID ?? 0] }
            guard length >= 2, end <= bytes.count else { return nil }
            if marker == 0xDB {
                guard let defined = quantizationTables(in: bytes, from: index + 4, to: end) else { return nil }
                tables.merge(defined) { first, _ in first }
            } else if (0xC0...0xC2).contains(marker), luminanceID == nil {
                guard length >= 11 else { return nil }
                luminanceID = bytes[index + 12]
            }
            index = end
        }
        return nil
    }

    private static func quantizationTables(in bytes: [UInt8], from start: Int, to end: Int) -> [UInt8: [Int]]? {
        var tables: [UInt8: [Int]] = [:]
        var position = start
        while position < end {
            let precision = bytes[position] >> 4, id = bytes[position] & 0x0F
            let width = precision == 0 ? 1 : 2
            guard precision <= 1, position + 1 + 64 * width <= end else { return nil }
            tables[id] = tables[id] ?? (0..<64).map { item in
                let offset = position + 1 + item * width
                return width == 1 ? Int(bytes[offset]) : Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            }
            position += 1 + 64 * width
        }
        return tables
    }
}
