import Foundation
import ImageIO
import PDFKit

nonisolated struct AutomationMediaService: Sendable {
    func perform(_ action: AutomationAction, source: URL, expected: FileFingerprint,
                 willPublish: @escaping @Sendable (URL) async throws -> Void = { _ in }) async throws -> AutomationActionOutput {
        let access = source.startAccessingSecurityScopedResource()
        let parent = source.deletingLastPathComponent()
        let parentAccess = parent.startAccessingSecurityScopedResource()
        defer {
            if access { source.stopAccessingSecurityScopedResource() }
            if parentAccess { parent.stopAccessingSecurityScopedResource() }
        }
        try check(source, expected)
        guard let file = FileTypeService().inspect([source]).files.first else { throw OptimizationError.unsupportedInput }
        let temporary = try FileOutputService().makeTemporaryFile(in: FileManager.default.temporaryDirectory)
        defer { FileOutputService().removeTemporaryFile(temporary) }
        let work = temporary.deletingLastPathComponent()
        if action.kind == .compress {
            return try await compress(action, file: file, work: work, expected: expected, willPublish: willPublish)
        }
        let candidate: URL
        switch action.kind {
        case .convert: candidate = try convert(action, file: file, work: work)
        case .resize: candidate = try resize(action, file: file, work: work)
        case .removeMetadata: candidate = try removeMetadata(action, file: file, work: work)
        default: throw OptimizationError.unsupportedInput
        }
        let output = try await publish(candidate, name: candidate.lastPathComponent, original: source,
                                       expected: expected, willPublish: willPublish)
        return AutomationActionOutput(url: output, message: action.kind.rawValue + " completed", savedBytes: 0, compressedBytes: 0)
    }

    private func compress(_ action: AutomationAction, file: FileItem, work: URL, expected: FileFingerprint,
                          willPublish: @escaping @Sendable (URL) async throws -> Void) async throws -> AutomationActionOutput {
        let outcome = try file.isPDF
            ? PDFOptimizationService().optimize(file, in: work, options: PDFOptimizationOptions(preset: action.preset))
            : ImageOptimizationService().optimize(file, in: work, preset: action.preset, palette: action.palette ?? .off)
        switch outcome {
        case .saved(let result):
            let output: URL
            if action.replacement == .keepBoth {
                output = try await publish(result.outputURL, name: result.outputURL.lastPathComponent,
                    original: file.url, expected: expected, willPublish: willPublish)
            } else {
                try await willPublish(file.url)
                try Task.checkCancellation()
                try check(file.url, expected)
                output = try SafeFileReplacementService().replace(source: file.url, candidate: result.outputURL,
                    expected: expected, trashOriginal: action.replacement == .moveOriginalToTrash)
            }
            return AutomationActionOutput(url: output, message: "Compressed", savedBytes: result.originalBytes - result.outputBytes,
                                          compressedBytes: result.originalBytes)
        case .noReduction:
            try check(file.url, expected)
            let suffix = file.url.pathExtension.isEmpty ? "" : "." + file.url.pathExtension
            let output = action.replacement == .keepBoth
                ? try await publish(file.url, name: file.url.deletingPathExtension().lastPathComponent + "-optimized" + suffix,
                                    original: file.url, expected: expected, willPublish: willPublish)
                : file.url
            return AutomationActionOutput(url: output, message: "Already small; continued without compression", savedBytes: 0,
                                          compressedBytes: expected.size)
        }
    }

    private func publish(_ candidate: URL, name: String, original: URL, expected: FileFingerprint,
                         willPublish: @escaping @Sendable (URL) async throws -> Void) async throws -> URL {
        try check(original, expected)
        return try await AutomationFileOperations().transfer(source: candidate, to: original.deletingLastPathComponent(),
            name: name, move: false, expected: FileFingerprint.read(candidate), willPublish: { output in
                try await willPublish(output)
                try check(original, expected)
            })
    }

    private func convert(_ action: AutomationAction, file: FileItem, work: URL) throws -> URL {
        guard file.isImage else { throw OptimizationError.unsupportedInput }
        if action.format == "pdf" {
            guard let output = try PDFConversionService().imagesToPDF([file], in: work, layout: .imageSize).outputURLs.first else {
                throw ConversionError.cannotEncode
            }
            return output
        }
        guard let format = ConversionFormat(rawValue: action.format) else { throw ConversionError.unsupportedOutput }
        return try ImageConversionService().convert(file, to: format, in: work,
            options: ConversionOptions(jpegQuality: action.quality)).outputURL
    }

    private func resize(_ action: AutomationAction, file: FileItem, work: URL) throws -> URL {
        let service = ImageResizeService()
        let original = try service.displayDimensions(for: file)
        let dimensions = try ResizeOptions(preset: .custom, width: action.width, height: action.height)
            .dimensions(width: original.width, height: original.height)
        guard let format = ConversionFormat.sourceFormat(for: file.contentTypeIdentifier),
              let source = CGImageSourceCreateWithURL(file.url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw OptimizationError.unsupportedInput
        }
        if format == .png { try OxipngService().validateRewrite(of: file.url) }
        let prepared = try service.preparedImage(source, properties: properties, dimensions: dimensions, removeMetadata: false)
        let candidate = work.appendingPathComponent(file.url.deletingPathExtension().lastPathComponent + "-resized." + format.fileExtension)
        try ImageOptimizationService().encodeResized(prepared.image, properties: prepared.properties,
            format: format, preset: action.preset, jpegQuality: format == .jpeg ? action.quality : nil, to: candidate)
        guard let result = CGImageSourceCreateWithURL(candidate as CFURL, nil),
              CGImageSourceGetType(result) as String? == format.typeIdentifier,
              CGImageSourceGetStatusAtIndex(result, 0) == .statusComplete,
              let image = CGImageSourceCreateImageAtIndex(result, 0, nil),
              image.width == dimensions.width, image.height == dimensions.height else { throw ConversionError.cannotEncode }
        return candidate
    }

    private func removeMetadata(_ action: AutomationAction, file: FileItem, work: URL) throws -> URL {
        if file.isPDF { return try stripPDF(file, work: work) }
        guard let format = ConversionFormat.sourceFormat(for: file.contentTypeIdentifier) else {
            throw OptimizationError.unsupportedInput
        }
        return try ImageConversionService().convert(file, to: format, in: work,
            options: ConversionOptions(jpegQuality: 1, stripMetadata: true)).outputURL
    }

    private func stripPDF(_ file: FileItem, work: URL) throws -> URL {
        try PDFOptimizationValidation.inspect(file.url, stronger: false)
        guard let document = PDFDocument(url: file.url), !document.isLocked, document.pageCount > 0 else {
            throw OptimizationError.unsupportedInput
        }
        let navigation = try PDFNavigationService.snapshot(document)
        document.documentAttributes = nil
        let candidate = work.appendingPathComponent(file.url.deletingPathExtension().lastPathComponent + "-clean.pdf")
        guard document.write(to: candidate), let result = PDFDocument(url: candidate),
              result.pageCount == document.pageCount,
              try PDFNavigationService.snapshot(result) == navigation else { throw ConversionError.cannotEncode }
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let before = document.page(at: index), let after = result.page(at: index),
                  before.string == after.string, before.rotation == after.rotation,
                  before.bounds(for: .mediaBox) == after.bounds(for: .mediaBox),
                  before.bounds(for: .cropBox) == after.bounds(for: .cropBox),
                  before.annotations.count == after.annotations.count else { throw ConversionError.cannotEncode }
        }
        return candidate
    }

    private func check(_ source: URL, _ expected: FileFingerprint) throws {
        try AutomationFileOperations.validateAncestors(source)
        guard expected.matches(try FileFingerprint.read(source)) else { throw WatchError.sourceChanged }
    }
}
