import Foundation

struct SelectionActionEntry: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let originalBytes: Int64
    let report: FileActionReport?
    let errorMessage: String?
}

struct SelectionActionService: Sendable {
    nonisolated init() {}

    nonisolated func execute(_ action: FileAction, files: [FileItem], directory: URL?,
                             settings: FileActionSettings,
                             progress: @Sendable (String) -> Void) async throws -> [SelectionActionEntry] {
        guard FileAction.common(for: files).contains(action), let first = files.first else {
            throw ConversionError.unsupportedInput
        }
        let grouped = action.kind == .imagePDF || action.kind == .mergePDFs
        let jobs = grouped ? [first] : files
        var entries: [SelectionActionEntry] = []
        for (index, file) in jobs.enumerated() {
            if Task.isCancelled { break }
            progress("\(index + 1) of \(jobs.count): \(file.fileName)")
            do {
                let report = try await FileActionService().execute(action, for: file, selection: files,
                    in: directory ?? file.url.deletingLastPathComponent(), settings: settings,
                    progress: { detail in progress("\(index + 1) of \(jobs.count): \(file.fileName) - \(detail)") })
                entries.append(SelectionActionEntry(fileName: grouped ? "\(files.count) files" : file.fileName,
                                                    originalBytes: report.compression?.originalBytes ?? file.fileSize,
                                                    report: report, errorMessage: nil))
            } catch {
                if error is CancellationError { break }
                if jobs.count == 1 { throw error }
                entries.append(SelectionActionEntry(fileName: file.fileName, originalBytes: file.fileSize, report: nil,
                    errorMessage: (error as? LocalizedError)?.errorDescription ?? "Operation failed."))
            }
        }
        return entries
    }
}
