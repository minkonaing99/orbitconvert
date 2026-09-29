import Foundation

struct BatchOptimizationFailure: Sendable {
    let fileName: String
    let message: String
}

struct BatchOptimizationResult: Sendable {
    let attemptedCount: Int
    let saved: [CompressionResult]
    let skippedCount: Int
    let failures: [BatchOptimizationFailure]
    let originalBytes: Int64
    let outputBytes: Int64
    let cancelled: Bool

    nonisolated var successCount: Int { saved.count + skippedCount }
    nonisolated var savingsBytes: Int64 { originalBytes - outputBytes }
    nonisolated var savingsPercentage: Double {
        CompressionResult.savingsPercentage(original: originalBytes, output: outputBytes)
    }
}

struct BatchOptimizationService: Sendable {
    nonisolated init() {}

    nonisolated func optimize(_ files: [FileItem], in directory: URL,
                              preset: CompressionPreset = .balanced,
                              jpegQuality: Double = 0.85, removeMetadata: Bool = false,
                              progress: @Sendable (Int, Int) -> Void = { _, _ in }) -> BatchOptimizationResult {
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }
        var saved: [CompressionResult] = []
        var skipped = 0
        var failures: [BatchOptimizationFailure] = []
        var originalBytes: Int64 = 0
        var outputBytes: Int64 = 0
        for (index, file) in files.enumerated() {
            if Task.isCancelled { break }
            progress(index + 1, files.count)
            do {
                let outcome = file.isPDF
                    ? try PDFOptimizationService().optimize(
                        file, in: directory,
                        options: PDFOptimizationOptions(preset: preset, removeMetadata: removeMetadata)
                    )
                    : try ImageOptimizationService().optimize(
                        file, in: directory, preset: preset,
                        jpegQuality: jpegQuality, removeMetadata: removeMetadata
                    )
                switch outcome {
                case .saved(let result):
                    saved.append(result)
                    originalBytes += result.originalBytes
                    outputBytes += result.outputBytes
                case .noReduction(let original, _):
                    skipped += 1
                    originalBytes += original
                    outputBytes += original
                }
            } catch {
                failures.append(BatchOptimizationFailure(
                    fileName: file.fileName,
                    message: (error as? LocalizedError)?.errorDescription ?? "Optimization failed."
                ))
            }
        }
        return BatchOptimizationResult(attemptedCount: files.count, saved: saved,
                                       skippedCount: skipped, failures: failures,
                                       originalBytes: originalBytes, outputBytes: outputBytes,
                                       cancelled: Task.isCancelled)
    }
}
