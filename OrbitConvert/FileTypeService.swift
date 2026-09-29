import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ConversionFormat: String, CaseIterable, Identifiable, Sendable {
    case png, jpeg, heic, tiff

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        }
    }

    nonisolated var typeIdentifier: String {
        switch self {
        case .png: UTType.png.identifier
        case .jpeg: UTType.jpeg.identifier
        case .heic: UTType.heic.identifier
        case .tiff: UTType.tiff.identifier
        }
    }

    nonisolated var fileExtension: String { self == .jpeg ? "jpg" : rawValue }

    nonisolated static func sourceFormat(for identifier: String) -> Self? {
        if identifier == UTType.heif.identifier { return .heic }
        return allCases.first { $0.typeIdentifier == identifier }
    }
}

struct FileItem: Identifiable, Sendable {
    let url: URL
    let fileName: String
    let fileExtension: String
    let contentTypeIdentifier: String
    let contentTypeName: String
    let fileSize: Int64
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let thumbnailData: Data
    let supportedConversions: [ConversionFormat]

    var id: URL { url }
}

struct FileTypeResult: Sendable {
    let files: [FileItem]
    let issues: [FileIntakeIssue]
}

struct FileTypeService: Sendable {
    nonisolated func inspect(_ urls: [URL]) -> FileTypeResult {
        let outcomes = urls.map(inspectOne)
        return FileTypeResult(
            files: outcomes.compactMap { if case .success(let file) = $0 { file } else { nil } },
            issues: outcomes.compactMap { if case .failure(let issue) = $0 { issue } else { nil } }
        )
    }

    nonisolated private func inspectOne(_ url: URL) -> Result<FileItem, FileIntakeIssue> {
        let name = url.lastPathComponent
        guard url.isFileURL else {
            return .failure(FileIntakeIssue(name: name, message: "Only local files can be imported."))
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentTypeKey])
            guard values.isRegularFile == true, FileManager.default.isReadableFile(atPath: url.path) else {
                return .failure(FileIntakeIssue(name: name, message: "This file is unavailable or cannot be read."))
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let type = CGImageSourceGetType(source) else {
                let message = values.contentType?.conforms(to: .image) == true
                    ? "This image could not be opened; it may be damaged."
                    : "Only PNG, JPEG, HEIC, and TIFF images are supported."
                return .failure(FileIntakeIssue(name: name, message: message))
            }
            let identifier = type as String
            guard let format = ConversionFormat.sourceFormat(for: identifier) else {
                return .failure(FileIntakeIssue(name: name, message: "This image format is not supported yet."))
            }
            guard CGImageSourceGetCount(source) == 1 else {
                return .failure(FileIntakeIssue(name: name, message: "Multi-image files are not supported yet."))
            }
            guard CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                  let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
                  width > 0, height > 0,
                  let thumbnail = thumbnailData(from: source),
                  let size = values.fileSize else {
                return .failure(FileIntakeIssue(name: name, message: "This image could not be opened; it may be damaged."))
            }
            let available = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
            let outputs = ConversionFormat.allCases.filter { $0 != format && available.contains($0.typeIdentifier) }
            return .success(FileItem(
                url: url, fileName: name, fileExtension: url.pathExtension,
                contentTypeIdentifier: identifier, contentTypeName: UTType(identifier)?.localizedDescription ?? format.label,
                fileSize: Int64(size), creationDate: values.creationDate,
                pixelWidth: width, pixelHeight: height,
                thumbnailData: thumbnail, supportedConversions: outputs
            ))
        } catch {
            return .failure(FileIntakeIssue(name: name, message: "This file is unavailable or cannot be read."))
        }
    }

    nonisolated private func thumbnailData(from source: CGImageSource) -> Data? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
