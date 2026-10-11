import Foundation
import PDFKit

struct PDFOptimizationOptions: Sendable {
    let strongerCompression: Bool
    let preset: CompressionPreset
    let targetDPI: Int?
    let jpegQuality: Double?
    let removeMetadata: Bool
    let preserveBookmarks: Bool
    let preserveLinks: Bool

    nonisolated init(preset: CompressionPreset = .balanced, targetDPI: Int? = nil,
                     jpegQuality: Double? = nil, removeMetadata: Bool = false,
                     preserveBookmarks: Bool = true, preserveLinks: Bool = true, strongerCompression: Bool = false) {
        self.strongerCompression = strongerCompression
        self.preset = preset
        self.targetDPI = targetDPI
        self.jpegQuality = jpegQuality
        self.removeMetadata = removeMetadata
        self.preserveBookmarks = preserveBookmarks
        self.preserveLinks = preserveLinks
    }

    nonisolated func validateForNativeBackend() throws {
        guard targetDPI == nil, jpegQuality == nil, preset != .custom else {
            throw OptimizationError.unsupportedPreset
        }
    }
}

struct PDFOptimizationService: Sendable {
    private let output = FileOutputService()

    nonisolated init() {}

    nonisolated func optimize(_ file: FileItem, in directory: URL,
                              options: PDFOptimizationOptions = PDFOptimizationOptions()) throws -> OptimizationOutcome {
        guard file.isPDF else { throw OptimizationError.unsupportedInput }
        if !options.strongerCompression { try options.validateForNativeBackend() }
        let sourceScoped = file.url.startAccessingSecurityScopedResource()
        defer { if sourceScoped { file.url.stopAccessingSecurityScopedResource() } }
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        try PDFOptimizationValidation.inspect(file.url, stronger: options.strongerCompression)
        guard let document = PDFDocument(url: file.url), !document.isLocked,
              document.pageCount > 0,
              let originalSize = try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw OptimizationError.unsupportedInput
        }
        if options.removeMetadata { document.documentAttributes = nil }
        let temporary = try output.makeTemporaryFile(in: directory)
        defer { output.removeTemporaryFile(temporary) }
        if options.strongerCompression {
            try GhostscriptService().optimize(source: file.url, destination: temporary, preset: options.preset)
            guard let optimized = PDFDocument(url: temporary) else { throw OptimizationError.cannotEncode }
            try PDFNavigationService.restore(from: document, to: optimized)
            if options.removeMetadata { optimized.documentAttributes = nil }
            let rewritten = temporary.deletingLastPathComponent().appendingPathComponent("navigation.pdf")
            guard optimized.write(to: rewritten) else { throw OptimizationError.cannotEncode }
            try FileManager.default.removeItem(at: temporary)
            try FileManager.default.moveItem(at: rewritten, to: temporary)
        } else {
            guard document.write(to: temporary, withOptions: writeOptions(for: options.preset)) else {
                throw OptimizationError.cannotEncode
            }
        }
        guard let candidate = PDFDocument(url: temporary), !candidate.isLocked,
              preservesStructure(source: document, candidate: candidate, options: options),
              let candidateSize = try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw OptimizationError.cannotEncode
        }
        if options.strongerCompression {
            guard try PDFNavigationService.snapshot(document) == PDFNavigationService.snapshot(candidate) else {
                throw OptimizationError.cannotEncode
            }
        }
        try Task.checkCancellation()
        guard candidateSize < originalSize else {
            return .noReduction(originalBytes: Int64(originalSize), candidateBytes: Int64(candidateSize))
        }
        let stem = file.url.deletingPathExtension().lastPathComponent + "-optimized"
        let url = try output.publish(temporary, stem: stem, fileExtension: "pdf", in: directory)
        return .saved(CompressionResult(originalURL: file.url, outputURL: url,
                                        originalBytes: Int64(originalSize), outputBytes: Int64(candidateSize)))
    }

    nonisolated private func writeOptions(for preset: CompressionPreset) -> [PDFDocumentWriteOption: Any] {
        switch preset {
        case .lossless: [:]
        case .balanced: [.saveImagesAsJPEGOption: true]
        case .aggressive: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
        case .custom: [:]
        }
    }

    nonisolated private func preservesStructure(source: PDFDocument, candidate: PDFDocument,
                                                options: PDFOptimizationOptions) -> Bool {
        guard candidate.pageCount == source.pageCount else { return false }
        for index in 0..<source.pageCount {
            guard let before = source.page(at: index), let after = candidate.page(at: index),
                  before.string == after.string,
                  before.rotation == after.rotation,
                  before.bounds(for: .mediaBox) == after.bounds(for: .mediaBox),
                  before.bounds(for: .cropBox) == after.bounds(for: .cropBox) else { return false }
            if options.preserveLinks {
                let sourceLinks = before.annotations.filter { $0.action is PDFActionURL }.count
                let resultLinks = after.annotations.filter { $0.action is PDFActionURL }.count
                guard sourceLinks == resultLinks else { return false }
            }
        }
        if options.preserveBookmarks {
            guard source.outlineRoot?.numberOfChildren == candidate.outlineRoot?.numberOfChildren else { return false }
        }
        return true
    }
}
