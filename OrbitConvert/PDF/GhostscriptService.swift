import Foundation

struct GhostscriptService: Sendable {
    nonisolated init() {}

    nonisolated func optimize(source: URL, destination: URL, preset: CompressionPreset) throws {
        guard preset == .balanced || preset == .aggressive else { throw OptimizationError.unsupportedPreset }
        let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 0, bytes <= 256_000_000 else { throw DocumentConversionError.protectedPDF }
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        try FileManager.default.copyItem(at: source, to: job.appendingPathComponent("input.pdf"))
        let dpi = preset == .aggressive ? "100" : "150"
        let arguments = ["-dSAFER", "-dBATCH", "-dNOPAUSE", "-dQUIET", "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.7", "-dDetectDuplicateImages=true", "-dCompressFonts=true",
            "-dDownsampleColorImages=true", "-dColorImageDownsampleType=/Bicubic",
            "-dColorImageResolution=" + dpi, "-dColorImageDownsampleThreshold=1.5",
            "-dDownsampleGrayImages=true", "-dGrayImageDownsampleType=/Bicubic",
            "-dGrayImageResolution=" + dpi, "-dGrayImageDownsampleThreshold=1.5",
            "-dDownsampleMonoImages=true", "-dMonoImageResolution=300",
            "-dAutoFilterColorImages=false", "-dColorImageFilter=/DCTEncode",
            "-dAutoFilterGrayImages=false", "-dGrayImageFilter=/DCTEncode",
            "-sOutputFile=output.pdf", "-f", "input.pdf"]
        try BundledDocumentTool().run("gs", arguments: arguments, in: job, timeout: .seconds(120))
        let output = job.appendingPathComponent("output.pdf")
        let outputBytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard outputBytes > 0, outputBytes <= 256_000_000 else { throw DocumentConversionError.invalidOutput }
        try FileManager.default.copyItem(at: output, to: destination)
    }
}
