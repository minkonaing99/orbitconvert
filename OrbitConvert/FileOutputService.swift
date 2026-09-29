import Darwin
import Foundation

enum ConversionError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedInput
    case unsupportedOutput
    case cannotDecode
    case cannotEncode
    case cannotWriteFile
    case permissionDenied
    case invalidDestination
    case invalidQuality
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedInput: "This image format is not supported."
        case .unsupportedOutput: "This output format is unavailable on this Mac."
        case .cannotDecode: "This image could not be opened; it may be damaged."
        case .cannotEncode: "This image could not be converted."
        case .cannotWriteFile: "The result could not be saved. Check available space and try another folder."
        case .permissionDenied: "OrbitConvert cannot save in this folder. Choose a folder to continue."
        case .invalidDestination: "Choose an available output folder."
        case .invalidQuality: "JPEG quality must be between 0 and 1."
        case .imageTooLarge: "This image is too large for the selected conversion options."
        }
    }
}

struct FileOutputService: Sendable {
    nonisolated func makeTemporaryFile(in directory: URL) throws -> URL {
        guard directory.isFileURL else { throw ConversionError.invalidDestination }
        var template = Array(directory.appendingPathComponent(".orbitconvert-XXXXXX").path.utf8CString)
        let created = template.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress.flatMap { mkdtemp($0) }
        }
        guard created != nil else { throw Self.writeError(for: errno) }
        return URL(fileURLWithPath: String(cString: template)).appendingPathComponent("image")
    }

    nonisolated func publish(_ temporary: URL, beside source: URL, as format: ConversionFormat, in directory: URL) throws -> URL {
        guard source.isFileURL, temporary.isFileURL, directory.isFileURL,
              temporary.lastPathComponent == "image",
              temporary.deletingLastPathComponent().lastPathComponent.hasPrefix(".orbitconvert-"),
              temporary.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw ConversionError.invalidDestination
        }
        let stem = source.deletingPathExtension().lastPathComponent
        var suffix = 0
        while true {
            let name = stem + (suffix == 0 ? "" : "-\(suffix)") + "." + format.fileExtension
            let output = directory.appendingPathComponent(name)
            let result = temporary.path.withCString { oldPath in
                output.path.withCString { newPath in link(oldPath, newPath) }
            }
            if result == 0 {
                removeTemporaryFile(temporary)
                return output
            }
            let code = errno
            guard code == EEXIST else { throw Self.writeError(for: code) }
            guard suffix < Int.max else { throw ConversionError.cannotWriteFile }
            suffix += 1
        }
    }

    nonisolated func removeTemporaryFile(_ temporary: URL) {
        guard temporary.lastPathComponent == "image",
              temporary.deletingLastPathComponent().lastPathComponent.hasPrefix(".orbitconvert-") else { return }
        try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent())
    }

    nonisolated static func writeError(for code: Int32) -> ConversionError {
        switch code {
        case EACCES, EPERM: .permissionDenied
        case ENOENT, ENOTDIR: .invalidDestination
        default: .cannotWriteFile
        }
    }
}
