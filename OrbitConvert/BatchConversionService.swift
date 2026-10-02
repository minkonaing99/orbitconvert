import Foundation

struct BatchConversionResult: Sendable {
    let attemptedCount: Int
    let outputURLs: [URL]
    let failures: [BatchOptimizationFailure]
    let cancelled: Bool
}

struct BatchConversionService: Sendable {
    nonisolated init() {}

    nonisolated static func commonFormats(for files: [FileItem]) -> [ConversionFormat] {
        guard files.count > 1, files.allSatisfy({ $0.isImage }) else { return [] }
        return [ConversionFormat.jpeg, .png].filter { format in
            files.allSatisfy { $0.supportedConversions.contains(format) }
        }
    }

    nonisolated func convert(_ files: [FileItem], to format: ConversionFormat, in directory: URL,
                             options: ConversionOptions = ConversionOptions(),
                             progress: @Sendable (Int, Int) -> Void = { _, _ in }) -> BatchConversionResult {
        guard Self.commonFormats(for: files).contains(format) else {
            return BatchConversionResult(attemptedCount: files.count, outputURLs: [],
                                         failures: [BatchOptimizationFailure(fileName: "Selection",
                                                                             message: "Not all selected files can convert to \(format.label).")],
                                         cancelled: false)
        }
        var outputURLs: [URL] = []
        var failures: [BatchOptimizationFailure] = []
        for (index, file) in files.enumerated() {
            if Task.isCancelled { break }
            progress(index + 1, files.count)
            do {
                let result = try ImageConversionService().convert(file, to: format,
                                                                  in: directory, options: options)
                outputURLs.append(result.outputURL)
            } catch {
                failures.append(BatchOptimizationFailure(
                    fileName: file.fileName,
                    message: (error as? LocalizedError)?.errorDescription ?? "Conversion failed."
                ))
            }
        }
        return BatchConversionResult(attemptedCount: files.count, outputURLs: outputURLs,
                                     failures: failures, cancelled: Task.isCancelled)
    }
}
