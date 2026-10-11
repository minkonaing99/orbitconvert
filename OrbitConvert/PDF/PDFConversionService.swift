import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit

enum PDFPageLayout: String, CaseIterable, Identifiable, Sendable {
    case fit, imageSize, a4, letter

    nonisolated var id: String { rawValue }
    nonisolated var label: String {
        switch self {
        case .fit: "Fit to page"
        case .imageSize: "Image dimensions"
        case .a4: "A4"
        case .letter: "US Letter"
        }
    }

    nonisolated func pageSize(for image: CGImage) -> CGSize {
        switch self {
        case .fit, .letter: CGSize(width: 612, height: 792)
        case .imageSize: CGSize(width: image.width, height: image.height)
        case .a4: CGSize(width: 595, height: 842)
        }
    }
}

struct PDFOperationResult: Sendable {
    let outputURLs: [URL]
    let originalByteCount: Int64
    let outputByteCount: Int64
}

enum PDFOperationError: Error, LocalizedError, Sendable {
    case invalidInput, invalidPages, invalidOptions, cannotRender, cannotWrite

    var errorDescription: String? {
        switch self {
        case .invalidInput: "This PDF or image could not be opened."
        case .invalidPages: "Choose pages within the PDF's page range."
        case .invalidOptions: "Choose a valid resolution and JPEG quality."
        case .cannotRender: "A PDF page could not be rendered."
        case .cannotWrite: "The PDF result could not be created."
        }
    }
}

struct PDFConversionService: Sendable {
    private let output = FileOutputService()

    nonisolated init() {}

    nonisolated func imagesToPDF(_ files: [FileItem], in directory: URL,
                                 layout: PDFPageLayout = .fit) throws -> PDFOperationResult {
        guard !files.isEmpty, files.allSatisfy({ $0.isImage }) else { throw PDFOperationError.invalidInput }
        let scopes = files.map { ($0.url, $0.url.startAccessingSecurityScopedResource()) }
        defer { scopes.forEach { if $0.1 { $0.0.stopAccessingSecurityScopedResource() } } }
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }
        let document = PDFDocument()
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(file.url as CFURL, nil),
                  CGImageSourceGetCount(source) == 1,
                  let image = orientedImage(from: source),
                  let page = makePage(image: image, layout: layout) else { throw PDFOperationError.invalidInput }
            document.insert(page, at: index)
        }
        let stem = files.count == 1 ? files[0].url.deletingPathExtension().lastPathComponent : "images"
        let url = try save(document, stem: stem, expectedPages: files.count, in: directory)
        return PDFOperationResult(outputURLs: [url], originalByteCount: files.reduce(0) { $0 + $1.fileSize },
                                  outputByteCount: byteCount(of: url))
    }

    nonisolated func renderPDF(_ file: FileItem, as format: ConversionFormat, in directory: URL,
                               dpi: Int = 150, jpegQuality: Double = 0.90,
                               progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> PDFOperationResult {
        guard file.isPDF else { throw PDFOperationError.invalidInput }
        guard format == .png || format == .jpeg, (72...300).contains(dpi),
              jpegQuality.isFinite, (0...1).contains(jpegQuality) else { throw PDFOperationError.invalidOptions }
        let sourceScoped = file.url.startAccessingSecurityScopedResource()
        defer { if sourceScoped { file.url.stopAccessingSecurityScopedResource() } }
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: file.url), !document.isLocked,
              document.pageCount > 0 else { throw PDFOperationError.invalidInput }
        let stem = file.url.deletingPathExtension().lastPathComponent
        var urls: [URL] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            progress(index + 1, document.pageCount)
            guard let page = document.page(at: index) else { throw PDFOperationError.invalidPages }
            let name = document.pageCount == 1 ? stem : "\(stem)-page-\(String(format: "%03d", index + 1))"
            let temporary = try output.makeTemporaryFile(in: directory)
            defer { output.removeTemporaryFile(temporary) }
            try render(page, to: temporary, as: format, dpi: dpi, quality: jpegQuality)
            guard let source = CGImageSourceCreateWithURL(temporary as CFURL, nil),
                  CGImageSourceGetType(source) as String? == format.typeIdentifier,
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw PDFOperationError.cannotRender }
            urls.append(try output.publish(temporary, stem: name, fileExtension: format.fileExtension, in: directory))
        }
        return PDFOperationResult(outputURLs: urls, originalByteCount: byteCount(of: file.url),
                                  outputByteCount: urls.reduce(0) { $0 + byteCount(of: $1) })
    }

    nonisolated func extractPages(_ file: FileItem, pages: ClosedRange<Int>, in directory: URL) throws -> PDFOperationResult {
        guard file.isPDF else { throw PDFOperationError.invalidInput }
        let sourceScoped = file.url.startAccessingSecurityScopedResource()
        defer { if sourceScoped { file.url.stopAccessingSecurityScopedResource() } }
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }
        guard let source = PDFDocument(url: file.url), !source.isLocked,
              pages.lowerBound >= 1, pages.upperBound <= source.pageCount else { throw PDFOperationError.invalidPages }
        let document = PDFDocument()
        for (index, number) in pages.enumerated() {
            try Task.checkCancellation()
            guard let page = source.page(at: number - 1)?.copy() as? PDFPage else { throw PDFOperationError.invalidPages }
            document.insert(page, at: index)
        }
        let stem = file.url.deletingPathExtension().lastPathComponent + "-pages-\(pages.lowerBound)-\(pages.upperBound)"
        let url = try save(document, stem: stem, expectedPages: pages.count, in: directory)
        return PDFOperationResult(outputURLs: [url], originalByteCount: byteCount(of: file.url),
                                  outputByteCount: byteCount(of: url))
    }

    nonisolated func mergePDFs(_ files: [FileItem], in directory: URL) throws -> PDFOperationResult {
        guard files.count >= 2, files.allSatisfy(\.isPDF) else { throw PDFOperationError.invalidInput }
        let scopes = files.map { ($0.url, $0.url.startAccessingSecurityScopedResource()) }
        defer { scopes.forEach { if $0.1 { $0.0.stopAccessingSecurityScopedResource() } } }
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }
        let merged = PDFDocument()
        for file in files {
            try Task.checkCancellation()
            guard let source = PDFDocument(url: file.url), !source.isLocked,
                  source.pageCount > 0 else { throw PDFOperationError.invalidInput }
            for index in 0..<source.pageCount {
                try Task.checkCancellation()
                guard let page = source.page(at: index)?.copy() as? PDFPage else { throw PDFOperationError.invalidPages }
                merged.insert(page, at: merged.pageCount)
            }
        }
        let url = try save(merged, stem: "merged", expectedPages: merged.pageCount, in: directory)
        return PDFOperationResult(outputURLs: [url], originalByteCount: files.reduce(0) { $0 + $1.fileSize },
                                  outputByteCount: byteCount(of: url))
    }

    nonisolated private func orientedImage(from source: CGImageSource) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 100_000_000 / height else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ] as CFDictionary)
    }

    nonisolated private func makePage(image: CGImage, layout: PDFPageLayout) -> PDFPage? {
        let size = layout.pageSize(for: image)
        let platformImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        return PDFPage(image: platformImage, options: [
            .mediaBox: NSValue(rect: CGRect(origin: .zero, size: size)),
            .upscaleIfSmaller: true,
            .compressionQuality: 0.90
        ])
    }

    nonisolated private func save(_ document: PDFDocument, stem: String,
                                  expectedPages: Int, in directory: URL) throws -> URL {
        let temporary = try output.makeTemporaryFile(in: directory)
        defer { output.removeTemporaryFile(temporary) }
        guard document.write(to: temporary), let reopened = PDFDocument(url: temporary),
              !reopened.isLocked, reopened.pageCount == expectedPages else { throw PDFOperationError.cannotWrite }
        try Task.checkCancellation()
        return try output.publish(temporary, stem: stem, fileExtension: "pdf", in: directory)
    }

    nonisolated private func render(_ page: PDFPage, to url: URL, as format: ConversionFormat,
                                    dpi: Int, quality: Double) throws {
        let bounds = page.bounds(for: .mediaBox)
        let rotated = abs(page.rotation) % 180 == 90
        let pointWidth = Double(rotated ? bounds.height : bounds.width)
        let pointHeight = Double(rotated ? bounds.width : bounds.height)
        let pixelWidth = ceil(pointWidth * Double(dpi) / 72)
        let pixelHeight = ceil(pointHeight * Double(dpi) / 72)
        guard pixelWidth.isFinite, pixelHeight.isFinite,
              pixelWidth > 0, pixelHeight > 0,
              pixelWidth <= 100_000_000 / pixelHeight,
              let pdfPage = page.pageRef else { throw PDFOperationError.cannotRender }
        let width = Int(pixelWidth)
        let height = Int(pixelHeight)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PDFOperationError.cannotRender }
        if format == .jpeg {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        context.concatenate(pdfPage.getDrawingTransform(.mediaBox, rect: target, rotate: 0,
                                                        preserveAspectRatio: true))
        context.drawPDFPage(pdfPage)
        for annotation in page.annotations where annotation.shouldDisplay {
            context.saveGState()
            annotation.draw(with: .mediaBox, in: context)
            context.restoreGState()
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, format.typeIdentifier as CFString, 1, nil) else {
            throw PDFOperationError.cannotRender
        }
        let options: [String: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality as String: quality] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PDFOperationError.cannotWrite }
    }

    nonisolated private func byteCount(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
