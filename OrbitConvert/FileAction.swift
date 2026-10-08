struct FileAction: Identifiable, Hashable, Sendable {
    nonisolated enum Category: Sendable {
        case conversion, tool
    }

    nonisolated enum Kind: Hashable, Sendable {
        case convert(ConversionFormat)
        case markdownPDF, markdownDOCX
        case imagePDF, pdfJPEG, pdfPNG, extractPages, mergePDFs, compress, resize, compressToSize
    }

    let kind: Kind

    nonisolated var category: Category {
        switch kind {
        case .convert, .imagePDF, .pdfJPEG, .pdfPNG, .markdownPDF, .markdownDOCX: .conversion
        case .compress, .resize, .compressToSize, .extractPages, .mergePDFs: .tool
        }
    }

    nonisolated init(format: ConversionFormat) { kind = .convert(format) }
    nonisolated init(_ kind: Kind) { self.kind = kind }

    nonisolated var id: String {
        switch kind {
        case .convert(let format): "convert-\(format.rawValue)"
        case .markdownPDF: "markdown-pdf"
        case .markdownDOCX: "markdown-docx"
        case .imagePDF: "image-pdf"
        case .pdfJPEG: "pdf-jpeg"
        case .pdfPNG: "pdf-png"
        case .extractPages: "extract-pages"
        case .mergePDFs: "merge-pdfs"
        case .compress: "compress"
        case .compressToSize: "compress-to-size"
        case .resize: "resize"
        }
    }

    nonisolated var title: String {
        switch kind {
        case .convert(let format): format.label
        case .markdownPDF: "PDF"
        case .markdownDOCX: "DOCX"
        case .imagePDF: "PDF"
        case .pdfJPEG: "JPG"
        case .pdfPNG: "PNG"
        case .extractPages: "Extract Pages"
        case .mergePDFs: "Merge"
        case .compress: "Compress"
        case .compressToSize: "Compress to Size"
        case .resize: "Resize + Optimize"
        }
    }

    nonisolated var symbolName: String {
        switch kind {
        case .convert(let format):
            switch format {
            case .png: "square.on.square"
            case .jpeg: "photo"
            case .heic: "sparkles.rectangle.stack"
            case .tiff: "square.stack.3d.up"
            }
        case .imagePDF, .mergePDFs, .markdownPDF, .markdownDOCX: "doc.richtext"
        case .pdfJPEG, .pdfPNG: "photo"
        case .extractPages: "doc.on.doc"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .compressToSize: "arrow.down.to.line"
        case .resize: "arrow.up.left.and.arrow.down.right"
        }
    }

    nonisolated static func common(for files: [FileItem]) -> [FileAction] {
        guard let first = files.first else { return [] }
        return available(for: first, selection: files).filter { action in
            (files.count == 1 || action.kind != .extractPages) &&
                files.allSatisfy { available(for: $0, selection: files).contains(action) }
        }
    }

    nonisolated static func available(for file: FileItem, selection: [FileItem]) -> [FileAction] {
        if file.isMarkdown { return [FileAction(.markdownPDF), FileAction(.markdownDOCX)] }
        if file.isPDF {
            var actions = [FileAction(.compress), FileAction(.pdfJPEG), FileAction(.pdfPNG),
                           FileAction(.extractPages)]
            if selection.filter(\.isPDF).count > 1 { actions.append(FileAction(.mergePDFs)) }
            return actions
        }
        var actions = file.supportedConversions.map(FileAction.init(format:))
        actions.append(FileAction(.imagePDF))
        if [.jpeg, .png].contains(ConversionFormat.sourceFormat(for: file.contentTypeIdentifier)) {
            actions.append(FileAction(.compress))
        }
        if ConversionFormat.sourceFormat(for: file.contentTypeIdentifier) == .jpeg {
            actions.append(FileAction(.compressToSize))
        }
        if ImageResizeService.supports(file) { actions.append(FileAction(.resize)) }
        return actions
    }
}
