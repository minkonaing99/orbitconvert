import Darwin
import Foundation

nonisolated enum AutomationTransferError: Error, LocalizedError, Sendable {
    case publishedCopy(URL, String)

    var errorDescription: String? {
        switch self {
        case .publishedCopy(let url, let reason):
            "Saved a copy at \(url.path), but kept the source. \(reason)"
        }
    }
}

nonisolated struct AutomationFileOperations: Sendable {
    init() {}

    func transfer(source: URL, to directory: URL, name: String, move: Bool,
                  expected: FileFingerprint,
                  collisionName: (@Sendable (Int) throws -> String)? = nil,
                  willPublish: @Sendable (URL) async throws -> Void = { _ in }) async throws -> URL {
        guard source.isFileURL, directory.isFileURL else { throw ConversionError.invalidDestination }
        try validate(name)
        try Self.validateAncestors(source)
        try Self.validateAncestors(directory.appendingPathComponent(name))
        let sourceAccess = source.startAccessingSecurityScopedResource()
        let destinationAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            if destinationAccess { directory.stopAccessingSecurityScopedResource() }
        }
        try check(source, expected)
        try Task.checkCancellation()
        let requested = directory.appendingPathComponent(name)
        if move, requested.standardizedFileURL == source.standardizedFileURL { return source }
        let files = FileOutputService()
        let temporary = try files.makeTemporaryFile(in: directory)
        defer { files.removeTemporaryFile(temporary) }
        try FileManager.default.copyItem(at: source, to: temporary)
        _ = try FileFingerprint.read(temporary)
        guard try equalContents(source, temporary) else { throw WatchError.sourceChanged }
        try check(source, expected)
        let output = try await publish(temporary, source: source, directory: directory,
                                      name: name, expected: expected, collisionName: collisionName,
                                      willPublish: willPublish)
        if move { try removeSource(source, expected: expected, output: output) }
        return output
    }

    func finishMove(source: URL, expected: FileFingerprint, output: URL,
                    outputExpected: FileFingerprint) throws {
        let sourceAccess = source.startAccessingSecurityScopedResource()
        let outputAccess = output.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            if outputAccess { output.stopAccessingSecurityScopedResource() }
        }
        do {
            guard source.isFileURL, output.isFileURL,
                  source.standardizedFileURL != output.standardizedFileURL else {
                throw ConversionError.invalidDestination
            }
            try check(source, expected)
            try check(output, outputExpected)
            guard try equalContents(source, output) else { throw WatchError.sourceChanged }
            try check(output, outputExpected)
            try Task.checkCancellation()
            try check(source, expected)
            try FileManager.default.removeItem(at: source)
        } catch {
            throw AutomationTransferError.publishedCopy(output, error.localizedDescription)
        }
    }

    static func validateAncestors(_ url: URL) throws {
        var parent = url.deletingLastPathComponent().standardizedFileURL
        while parent.path != "/" {
            let values = try parent.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            // macOS exposes these system directories through root-level aliases.
            if values.isSymbolicLink == true && !["/tmp", "/var", "/etc"].contains(parent.path) {
                throw WatchError.unavailableFile
            }
            guard values.isDirectory == true || values.isSymbolicLink == true else { throw WatchError.unavailableFile }
            parent.deleteLastPathComponent()
        }
    }

    private func validate(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
              !name.contains("/"), !name.contains(":"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ConversionError.invalidDestination
        }
    }

    private func check(_ source: URL, _ expected: FileFingerprint) throws {
        try Self.validateAncestors(source)
        guard try expected.matches(FileFingerprint.read(source)) else { throw WatchError.sourceChanged }
    }

    private func equalContents(_ first: URL, _ second: URL) throws -> Bool {
        let left = try FileHandle(forReadingFrom: first)
        defer { try? left.close() }
        let right = try FileHandle(forReadingFrom: second)
        defer { try? right.close() }
        while true {
            try Task.checkCancellation()
            let a = try left.read(upToCount: 1_048_576) ?? Data()
            let b = try right.read(upToCount: 1_048_576) ?? Data()
            guard a == b else { return false }
            if a.isEmpty { return true }
        }
    }

    private func publish(_ temporary: URL, source: URL, directory: URL, name: String,
                         expected: FileFingerprint,
                         collisionName: (@Sendable (Int) throws -> String)?,
                         willPublish: @Sendable (URL) async throws -> Void) async throws -> URL {
        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var suffix = 0
        while true {
            guard suffix < Int.max else { throw ConversionError.cannotWriteFile }
            let fallback = suffix == 0 ? name : stem + "-\(suffix)" + (ext.isEmpty ? "" : "." + ext)
            let candidate = try collisionName?(suffix + 1) ?? fallback
            try validate(candidate)
            let output = directory.appendingPathComponent(candidate)
            try Task.checkCancellation()
            try await willPublish(output)
            try Task.checkCancellation()
            try check(source, expected)
            try Self.validateAncestors(output)
            let result = temporary.path.withCString { old in
                output.path.withCString { new in link(old, new) }
            }
            if result == 0 { return output }
            let code = errno
            guard code == EEXIST else { throw FileOutputService.writeError(for: code) }
            suffix += 1
        }
    }

    private func removeSource(_ source: URL, expected: FileFingerprint, output: URL) throws {
        do {
            try Task.checkCancellation()
            try check(source, expected)
            try FileManager.default.removeItem(at: source)
        } catch {
            throw AutomationTransferError.publishedCopy(output, error.localizedDescription)
        }
    }
}
