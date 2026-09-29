struct FileAction: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case convert(ConversionFormat)
        case imagePDF, pdfJPEG, pdfPNG, extractPages, mergePDFs, compress
    }

    let kind: Kind

    nonisolated init(format: ConversionFormat) { kind = .convert(format) }
    nonisolated init(_ kind: Kind) { self.kind = kind }

    nonisolated var id: String {
        switch kind {
        case .convert(let format): "convert-\(format.rawValue)"
        case .imagePDF: "image-pdf"
        case .pdfJPEG: "pdf-jpeg"
        case .pdfPNG: "pdf-png"
        case .extractPages: "extract-pages"
        case .mergePDFs: "merge-pdfs"
        case .compress: "compress"
        }
    }

    nonisolated var title: String {
        switch kind {
        case .convert(let format): format.label
        case .imagePDF: "PDF"
        case .pdfJPEG: "JPG"
        case .pdfPNG: "PNG"
        case .extractPages: "Extract"
        case .mergePDFs: "Merge"
        case .compress: "Compress"
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
        case .imagePDF, .mergePDFs: "doc.richtext"
        case .pdfJPEG, .pdfPNG: "photo"
        case .extractPages: "doc.on.doc"
        case .compress: "arrow.down.right.and.arrow.up.left"
        }
    }

    nonisolated static func available(for file: FileItem, selection: [FileItem]) -> [FileAction] {
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
        return actions
    }
}
