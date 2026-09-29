struct FileAction: Identifiable, Hashable {
    let format: ConversionFormat

    var id: String { format.rawValue }
    var title: String { format.label }

    var symbolName: String {
        switch format {
        case .png: "square.on.square"
        case .jpeg: "photo"
        case .heic: "sparkles.rectangle.stack"
        case .tiff: "square.stack.3d.up"
        }
    }
}
