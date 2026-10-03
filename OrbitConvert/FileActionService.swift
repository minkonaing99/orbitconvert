import Foundation

struct FileActionSettings: Sendable {
    var resizeOptions = ResizeOptions()
    var markdownImageFolder: URL? = nil
    var markdownPDFStyle = MarkdownPDFStyle()
    var strongerPDFCompression = false
    let jpegQuality: Double
    let stripMetadata: Bool
    let compressionPreset: CompressionPreset
    let pdfDPI: Int
    let pdfLayout: PDFPageLayout
    let pageSelection: String
}

struct FileActionReport: Sendable {
    let outputURLs: [URL]
    let message: String
    let compression: CompressionResult?
}

struct FileActionService: Sendable {
    nonisolated init() {}

    nonisolated func execute(_ action: FileAction, for file: FileItem, selection: [FileItem],
                             in directory: URL, settings: FileActionSettings,
                             progress: @Sendable (String) -> Void = { _ in }) async throws -> FileActionReport {
        switch action.kind {
        case .resize:
            progress("Resizing and optimizing...")
            let outcome = try ImageResizeService().resize(
                file, in: directory, options: settings.resizeOptions,
                preset: settings.compressionPreset, jpegQuality: settings.jpegQuality,
                removeMetadata: settings.stripMetadata)
            switch outcome {
            case .saved(let result):
                let inspected = FileTypeService().inspect([result.outputURL]).files.first
                let dimensions = inspected.map { "\($0.pixelWidth) x \($0.pixelHeight) px. " } ?? ""
                return FileActionReport(outputURLs: [result.outputURL],
                    message: dimensions + "Saved \(result.outputURL.lastPathComponent)", compression: result)
            case .noReduction:
                return FileActionReport(outputURLs: [],
                    message: "No useful size reduction. Original kept.", compression: nil)
            }
        case .markdownPDF, .markdownDOCX:
            return try await MarkdownConversionService().convert(file, toDOCX: action.kind == .markdownDOCX,
                                                                 in: directory, imageFolder: settings.markdownImageFolder,
                                                                 pdfStyle: settings.markdownPDFStyle)
        case .convert(let format):
            let result = try ImageConversionService().convert(
                file, to: format, in: directory,
                options: ConversionOptions(jpegQuality: settings.jpegQuality, stripMetadata: settings.stripMetadata)
            )
            return FileActionReport(outputURLs: [result.outputURL],
                                    message: "Saved \(result.outputURL.lastPathComponent)", compression: nil)
        case .imagePDF:
            let images = selection.filter { $0.isImage }
            let result = try PDFConversionService().imagesToPDF(images, in: directory, layout: settings.pdfLayout)
            return pdfReport(result)
        case .pdfJPEG, .pdfPNG:
            let format: ConversionFormat
            switch action.kind {
            case .pdfJPEG: format = .jpeg
            default: format = .png
            }
            let result = try PDFConversionService().renderPDF(
                file, as: format, in: directory, dpi: settings.pdfDPI,
                jpegQuality: settings.jpegQuality,
                progress: { page, total in progress("Rendering page \(page) of \(total)") }
            )
            return pdfReport(result)
        case .extractPages:
            let pages = try parsePages(settings.pageSelection, pageCount: file.pageCount ?? 0)
            return pdfReport(try PDFConversionService().extractPages(file, pages: pages, in: directory))
        case .mergePDFs:
            return pdfReport(try PDFConversionService().mergePDFs(selection.filter(\.isPDF), in: directory))
        case .compress:
            progress("Compressing...")
            let outcome: OptimizationOutcome
            if file.isPDF {
                outcome = try PDFOptimizationService().optimize(
                    file, in: directory,
                    options: PDFOptimizationOptions(preset: settings.compressionPreset,
                                                    removeMetadata: settings.stripMetadata,
                                                    strongerCompression: settings.strongerPDFCompression)
                )
            } else {
                outcome = try ImageOptimizationService().optimize(
                    file, in: directory, preset: settings.compressionPreset,
                    jpegQuality: settings.jpegQuality, removeMetadata: settings.stripMetadata
                )
            }
            switch outcome {
            case .saved(let result):
                return FileActionReport(outputURLs: [result.outputURL],
                                        message: "Optimized \(result.outputURL.lastPathComponent)", compression: result)
            case .noReduction:
                return FileActionReport(outputURLs: [], message: "No useful size reduction. Original kept.", compression: nil)
            }
        }
    }

    nonisolated private func pdfReport(_ result: PDFOperationResult) -> FileActionReport {
        let message = result.outputURLs.count == 1
            ? "Saved \(result.outputURLs[0].lastPathComponent)"
            : "Saved \(result.outputURLs.count) files"
        return FileActionReport(outputURLs: result.outputURLs, message: message, compression: nil)
    }

    nonisolated func parsePages(_ input: String, pageCount: Int) throws -> ClosedRange<Int> {
        guard pageCount > 0 else { throw PDFOperationError.invalidPages }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.lowercased() == "all" { return 1...pageCount }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count <= 2, let first = Int(parts[0]), first >= 1 else { throw PDFOperationError.invalidPages }
        let last = parts.count == 2 ? Int(parts[1]) : first
        guard let last, last >= first, last <= pageCount else { throw PDFOperationError.invalidPages }
        return first...last
    }
}
