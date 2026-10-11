import Foundation

nonisolated enum WatchActivityOutcome: String, Codable, Sendable {
    case optimized, skipped, failed
}

nonisolated struct WatchActivity: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let fileName: String
    let outcome: WatchActivityOutcome
    let originalBytes: Int64
    let outputBytes: Int64
    let message: String
    var automation: AutomationRunDetails? = nil

    var savingsBytes: Int64 {
        if let automation { return automation.compressionSavedBytes }
        guard outcome == .optimized, originalBytes > 0, outputBytes >= 0 else { return 0 }
        return max(originalBytes - outputBytes, 0)
    }

    var savingsPercentage: Double {
        let total = automation?.compressionOriginalBytes ?? originalBytes
        guard total > 0 else { return 0 }
        return Double(savingsBytes) / Double(total) * 100
    }

    nonisolated init(fileName: String, outcome: WatchActivityOutcome,
                     originalBytes: Int64 = 0, outputBytes: Int64 = 0,
                     message: String = "", automation: AutomationRunDetails? = nil) {
        self.id = UUID()
        self.date = Date()
        self.fileName = fileName
        self.outcome = outcome
        self.originalBytes = originalBytes
        self.outputBytes = outputBytes
        self.message = message
        self.automation = automation
    }
}

nonisolated struct WatchJobResult: Sendable {
    let activity: WatchActivity
    let outputURL: URL?
    let retryable: Bool
    var checkpoint: AutomationCheckpoint? = nil
}

struct AutoOptimizationService: Sendable {
    nonisolated init() {}

    nonisolated func process(_ url: URL, in folder: WatchedFolder,
                             progress: @Sendable (OptimizationJobPhase) async -> Void = { _ in }) async -> WatchJobResult {
        do {
            var stale = false
            let scopedFolder = try URL(resolvingBookmarkData: folder.bookmarkData,
                                       options: .withSecurityScope, relativeTo: nil,
                                       bookmarkDataIsStale: &stale)
            guard scopedFolder.startAccessingSecurityScopedResource() else { throw WatchError.permissionLost }
            defer { scopedFolder.stopAccessingSecurityScopedResource() }
            guard !stale else { throw WatchError.permissionLost }
            await progress(.checkingFile)
            let stable = try await FileStabilityService().waitUntilStable(url)
            guard WatchFilePolicy.isEligibleFile(url, allowed: folder.supportedTypes) else {
                throw OptimizationError.unsupportedInput
            }
            let inspection = FileTypeService().inspect([url])
            guard let file = inspection.files.first,
                  let type = WatchFileType.actualType(file.contentTypeIdentifier),
                  folder.supportedTypes.contains(type) else { throw WatchError.unstableFile }
            let jobDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("OrbitConvert/Jobs/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: jobDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: jobDirectory) }
            await progress(.compressing)
            let outcome: OptimizationOutcome
            if file.isPDF {
                outcome = try PDFOptimizationService().optimize(
                    file, in: jobDirectory,
                    options: PDFOptimizationOptions(preset: folder.preset)
                )
            } else {
                outcome = try ImageOptimizationService().optimize(
                    file, in: jobDirectory, preset: folder.preset
                )
            }
            switch outcome {
            case .noReduction(let original, _):
                return WatchJobResult(activity: WatchActivity(
                    fileName: file.fileName, outcome: .skipped,
                    originalBytes: original, outputBytes: original,
                    message: "No useful reduction"), outputURL: nil, retryable: false)
            case .saved(let result):
                try Task.checkCancellation()
                await progress(.validating)
                let output: URL
                switch folder.replacementBehavior {
                case .replaceOriginal:
                    output = try SafeFileReplacementService().replace(
                        source: url, candidate: result.outputURL, expected: stable)
                case .moveOriginalToTrash:
                    output = try SafeFileReplacementService().replace(
                        source: url, candidate: result.outputURL, expected: stable, trashOriginal: true)
                case .keepBoth:
                    output = try SafeFileReplacementService().keepBoth(
                        source: url, candidate: result.outputURL, expected: stable)
                }
                let outputSize = Int64(try FileFingerprint.read(output).size)
                return WatchJobResult(activity: WatchActivity(
                    fileName: file.fileName, outcome: .optimized,
                    originalBytes: result.originalBytes, outputBytes: outputSize,
                    message: folder.replacementBehavior == .keepBoth ? "Saved optimized copy" : "Replaced original"),
                    outputURL: output, retryable: false)
            }
        } catch {
            let message: String
            if let known = error as? WatchError { message = known.localizedDescription }
            else if let known = error as? OptimizationError { message = known.localizedDescription }
            else if let known = error as? ConversionError { message = known.localizedDescription }
            else { message = "Optimization failed. Original kept." }
            return WatchJobResult(activity: WatchActivity(
                fileName: url.lastPathComponent, outcome: .failed,
                message: message),
                outputURL: nil, retryable: (error as? WatchError) == .unstableFile ||
                    (error as? OptimizationError) == .unsupportedInput)
        }
    }
}
