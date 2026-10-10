import Foundation

nonisolated enum QuickCompressionMode: String, CaseIterable, Identifiable {
    case keepBoth, replaceOriginal, chooseFolder
    var id: String { rawValue }
    init(savedValue: String?) { self = Self(rawValue: savedValue ?? "") ?? .keepBoth }
    var label: String {
        switch self {
        case .keepBoth: "Keep Both"
        case .replaceOriginal: "Replace Original"
        case .chooseFolder: "Choose Output Folder"
        }
    }
    var detail: String {
        switch self {
        case .keepBoth: "Save a smaller copy next to each original."
        case .replaceOriginal: "Replace each original with a smaller, checked copy. This cannot be undone."
        case .chooseFolder: "Save smaller copies in a folder you choose. Originals stay where they are."
        }
    }
}

nonisolated struct QuickCompressionSettings: Sendable {
    let preset: CompressionPreset
    let removeMetadata: Bool
    init(preset: CompressionPreset = .balanced, removeMetadata: Bool = false) {
        self.preset = preset
        self.removeMetadata = removeMetadata
    }
    init(defaults: UserDefaults) {
        let saved = CompressionPreset(rawValue: defaults.string(forKey: "defaultCompressionPreset") ?? "")
        preset = saved == .custom ? .balanced : saved ?? .balanced
        removeMetadata = defaults.bool(forKey: "removeMetadata")
    }
}

nonisolated struct QuickCompressionResult: Identifiable, Sendable {
    let source: URL
    let compression: CompressionResult?
    let message: String
    let failed: Bool
    var id: URL { source }
}

struct QuickCompressionService: Sendable {
    nonisolated init() {}

    nonisolated func run(_ urls: [URL], mode: QuickCompressionMode, destination: URL? = nil,
                         settings: QuickCompressionSettings,
                         progress: @Sendable (Int) -> Void = { _ in }) -> [QuickCompressionResult] {
        var results: [QuickCompressionResult] = []
        for (index, url) in urls.enumerated() {
            do {
                try Task.checkCancellation()
                let result = try compress(url, mode: mode, destination: destination, settings: settings)
                results.append(QuickCompressionResult(source: url, compression: result,
                    message: result == nil ? "Already small. Original kept." : "Compressed", failed: false))
            } catch is CancellationError {
                results.append(QuickCompressionResult(source: url, compression: nil,
                    message: "Canceled. Original kept.", failed: false))
            } catch {
                results.append(QuickCompressionResult(source: url, compression: nil,
                    message: error.localizedDescription, failed: true))
            }
            progress(index + 1)
        }
        return results
    }

    nonisolated private func compress(_ url: URL, mode: QuickCompressionMode, destination: URL?,
                                      settings: QuickCompressionSettings) throws -> CompressionResult? {
        guard url.isFileURL else { throw OptimizationError.unsupportedInput }
        if mode == .chooseFolder, destination == nil { throw ConversionError.invalidDestination }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let expected = try FileFingerprint.read(url)
        guard let file = FileTypeService().inspect([url]).files.first,
              file.isImage else { throw OptimizationError.unsupportedInput }
        let temporary = try FileOutputService().makeTemporaryFile(in: FileManager.default.temporaryDirectory)
        defer { FileOutputService().removeTemporaryFile(temporary) }
        let outcome = try ImageOptimizationService().optimize(file, in: temporary.deletingLastPathComponent(),
            preset: settings.preset, removeMetadata: settings.removeMetadata)
        guard case .saved(let result) = outcome else { return nil }
        try Task.checkCancellation()
        let output: URL
        switch mode {
        case .keepBoth:
            output = try SafeFileReplacementService().keepBoth(source: url, candidate: result.outputURL, expected: expected)
        case .replaceOriginal:
            output = try SafeFileReplacementService().replace(source: url, candidate: result.outputURL, expected: expected)
        case .chooseFolder:
            guard let destination else { throw ConversionError.invalidDestination }
            output = try publish(result, in: destination, expected: expected)
        }
        return CompressionResult(originalURL: url, outputURL: output,
            originalBytes: result.originalBytes, outputBytes: result.outputBytes)
    }

    nonisolated private func publish(_ result: CompressionResult, in directory: URL,
                                     expected: FileFingerprint) throws -> URL {
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        let service = FileOutputService()
        let temporary = try service.makeTemporaryFile(in: directory)
        defer { service.removeTemporaryFile(temporary) }
        try FileManager.default.copyItem(at: result.outputURL, to: temporary)
        try Task.checkCancellation()
        guard expected.matches(try FileFingerprint.read(result.originalURL)) else { throw WatchError.sourceChanged }
        return try service.publish(temporary,
            stem: result.originalURL.deletingPathExtension().lastPathComponent + "-optimized",
            fileExtension: result.outputURL.pathExtension, in: directory)
    }
}
