import Foundation

nonisolated enum AutomationWatchService {
    static func process(_ url: URL, folder: WatchedFolder, approved: AutomationPreviewItem? = nil,
                        resume: AutomationCheckpoint? = nil,
                        willPublish: @escaping @Sendable (URL) async throws -> Void,
                        didPublish: @escaping @Sendable (URL) async -> Void = { _ in }) async -> WatchJobResult {
        do {
            let root = try AutomationExecutionService.destination(folder.bookmarkData)
            let scoped = root.startAccessingSecurityScopedResource()
            defer { if scoped { root.stopAccessingSecurityScopedResource() } }
            var grants: [URL] = []
            for data in (resume?.rule.actions ?? []).compactMap(\.destinationBookmark) {
                let destination = try AutomationExecutionService.destination(data)
                if destination.startAccessingSecurityScopedResource() { grants.append(destination) }
            }
            defer { grants.forEach { $0.stopAccessingSecurityScopedResource() } }
            if resume == nil {
                guard WatchedFoldersController.isContained(url, in: root, recursive: folder.recursive) else {
                    throw WatchError.unavailableFile
                }
            }
            let stable = try await FileStabilityService().waitUntilStable(url)
            if let approved, approved.fingerprint?.matches(stable) != true { throw WatchError.sourceChanged }
            let rules = folder.effectiveRules
            let facts = try AutomationFileFacts.read(url, includeText: rules.contains { $0.conditions.contains { $0.field == .text } })
            let rule = try resume?.rule ?? approved?.rule ?? AutomationConditionService.firstMatch(rules, facts: facts,
                isSubfolder: url.deletingLastPathComponent().standardizedFileURL != root.standardizedFileURL)
            guard let rule else {
                return WatchJobResult(activity: WatchActivity(fileName: url.lastPathComponent,
                    outcome: .skipped, message: facts.textIssue ?? "No matching rule"), outputURL: nil, retryable: false)
            }
            guard stable.matches(try FileFingerprint.read(url)) else { throw WatchError.sourceChanged }
            if resume == nil, !WatchedFoldersController.isContained(url, in: root, recursive: folder.recursive) {
                throw WatchError.unavailableFile
            }
            let result = await AutomationExecutionService().run(url, rule: rule, resume: resume, expectedSource: stable, willPublish: willPublish, didPublish: didPublish)
            return WatchJobResult(activity: WatchActivity(fileName: resume?.original.url.lastPathComponent ?? url.lastPathComponent,
                outcome: result.failed ? .failed : .optimized, originalBytes: result.originalBytes,
                outputBytes: result.outputBytes, message: result.message, automation: result.details),
                outputURL: result.outputURL, retryable: false, checkpoint: result.checkpoint)
        } catch {
            return WatchJobResult(activity: WatchActivity(fileName: url.lastPathComponent, outcome: .failed,
                message: error.localizedDescription), outputURL: nil, retryable: false, checkpoint: resume)
        }
    }
}
