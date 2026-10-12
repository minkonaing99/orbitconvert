import Foundation

// Opt-in lossy palette reduction with the bundled pngquant (GPL v3, local build input only).
// The macOS build converts colors to sRGB and drops metadata chunks; callers must allow that.
nonisolated struct PngquantService: Sendable {
    static let qualityRange = "80-100"
    static let maxBytes: Int64 = 256_000_000
    static let maxPixels = 100_000_000
    private static let qualityTooLow: Int32 = 99
    private static let notSmaller: Int32 = 98

    init() {}

    /// Writes a palette PNG to `destination` and returns true. Returns false (skipped) when the input is too
    /// large, pngquant cannot meet the quality floor or shrink the file, or the helper fails or is missing,
    /// so callers fall back to lossless optimization. Cancellation still throws. Never overwrites `destination`.
    func quantize(_ source: URL, to destination: URL, timeout: Duration = .seconds(60)) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ConversionError.cannotWriteFile }
        guard Self.withinLimits(source) else { return false }
        do {
            return try run(source, to: destination, timeout: timeout)
        } catch is DocumentConversionError {
            return false
        }
    }

    private func run(_ source: URL, to destination: URL, timeout: Duration) throws -> Bool {
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        try FileManager.default.copyItem(at: source, to: job.appendingPathComponent("input.png"))
        let status = try BundledDocumentTool().run("pngquant",
            arguments: ["--quality=" + Self.qualityRange, "--speed", "3", "--skip-if-larger",
                        "--output", "output.png", "--", "input.png"],
            in: job, timeout: timeout, acceptedStatuses: [0, Self.qualityTooLow, Self.notSmaller])
        guard status == 0 else { return false }
        try FileManager.default.copyItem(at: job.appendingPathComponent("output.png"), to: destination)
        return true
    }

    // Checks file size and the declared IHDR dimensions before the helper allocates width x height pixels.
    static func withinLimits(_ url: URL) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) <= maxBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 24), header.count == 24,
              header.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]),
              header[12..<16] == Data("IHDR".utf8) else { return false }
        let width = header[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let height = header[20..<24].reduce(0) { $0 << 8 | Int($1) }
        return width > 0 && height > 0 && width <= maxPixels / height
    }
}
