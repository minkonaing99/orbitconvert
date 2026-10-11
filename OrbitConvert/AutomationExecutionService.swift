import Foundation

nonisolated struct AutomationExecutionService: Sendable {
    func run(_ source: URL, rule: AutomationRule, resume: AutomationCheckpoint? = nil, expectedSource: FileFingerprint? = nil,
             willPublish: @escaping @Sendable (URL) async throws -> Void = { _ in },
             didPublish: @escaping @Sendable (URL) async -> Void = { _ in }) async -> AutomationRunResult {
        var grants: [URL] = []
        defer { grants.forEach { $0.stopAccessingSecurityScopedResource() } }
        for data in rule.actions.compactMap(\.destinationBookmark) {
            if let url = try? destination(data), url.startAccessingSecurityScopedResource() { grants.append(url) }
        }
        do {
            try rule.validate()
            let facts = try resume?.original ?? AutomationFileFacts.read(source)
            if let expectedSource, resume == nil, !expectedSource.matches(facts.fingerprint) { throw WatchError.sourceChanged }
            return await execute(facts, rule: resume?.rule ?? rule, resume: resume, willPublish: willPublish, didPublish: didPublish)
        } catch {
            return AutomationRunResult(details: AutomationRunDetails(ruleName: rule.name, finalName: source.lastPathComponent,
                destination: source.deletingLastPathComponent().path, steps: [], dateFallback: false,
                compressionOriginalBytes: 0, compressionSavedBytes: 0), outputURL: nil, checkpoint: nil,
                failed: true, message: error.localizedDescription, originalBytes: 0, outputBytes: 0)
        }
    }

    private func execute(_ facts: AutomationFileFacts, rule: AutomationRule, resume: AutomationCheckpoint?,
                         willPublish: @escaping @Sendable (URL) async throws -> Void,
                         didPublish: @escaping @Sendable (URL) async -> Void) async -> AutomationRunResult {
        var working = resume?.workingURL ?? facts.url
        var expected = resume?.expected ?? facts.fingerprint
        var steps = resume?.steps ?? []
        var compressed = resume?.compressedBytes ?? 0
        var saved = resume?.savedBytes ?? 0
        let start = resume?.nextAction ?? 0
        for index in start..<rule.actions.count {
            let action = rule.actions[index]
            do {
                try Task.checkCancellation()
                try AutomationFileOperations.validateAncestors(working)
                guard expected.matches(try FileFingerprint.read(working)) else { throw WatchError.sourceChanged }
                let output: AutomationActionOutput
                if index == start, let cleanup = resume?.cleanupOutput, let cleanupExpected = resume?.cleanupExpected {
                    try AutomationFileOperations().finishMove(source: working, expected: expected,
                        output: cleanup, outputExpected: cleanupExpected)
                    output = AutomationActionOutput(url: cleanup, message: "Move completed", savedBytes: 0, compressedBytes: 0)
                } else {
                    output = try await perform(action, working: working, facts: facts, expected: expected, willPublish: willPublish)
                }
                await didPublish(output.url)
                steps.append(AutomationStepRecord(action: action.kind.rawValue, inputName: working.lastPathComponent,
                    outputName: output.url.lastPathComponent, destination: output.url.deletingLastPathComponent().path,
                    message: output.message, failed: false, savedBytes: output.savedBytes))
                working = output.url
                expected = try FileFingerprint.read(working)
                compressed += output.compressedBytes
                saved += output.savedBytes
            } catch {
                var cleanup: URL?
                if case AutomationTransferError.publishedCopy(let url, _) = error {
                    cleanup = url
                    await didPublish(url)
                }
                let checkpoint = AutomationCheckpoint(original: facts, rule: rule, workingURL: working,
                    expected: expected, nextAction: index, steps: steps, compressedBytes: compressed,
                    savedBytes: saved, cleanupOutput: cleanup ?? (index == start ? resume?.cleanupOutput : nil),
                    cleanupExpected: cleanup.flatMap { try? FileFingerprint.read($0) } ?? (index == start ? resume?.cleanupExpected : nil))
                let failed = AutomationStepRecord(action: action.kind.rawValue, inputName: working.lastPathComponent,
                    outputName: cleanup?.lastPathComponent ?? working.lastPathComponent,
                    destination: (cleanup ?? working).deletingLastPathComponent().path,
                    message: error is CancellationError ? "Canceled; completed steps are kept." : error.localizedDescription, failed: true)
                return result(facts, rule: rule, working: working, steps: steps + [failed],
                    compressed: compressed, saved: saved, checkpoint: checkpoint, message: failed.message)
            }
        }
        return result(facts, rule: rule, working: working, steps: steps, compressed: compressed,
            saved: saved, checkpoint: nil, message: "Rule completed")
    }

    private func result(_ facts: AutomationFileFacts, rule: AutomationRule, working: URL,
                        steps: [AutomationStepRecord], compressed: Int64, saved: Int64,
                        checkpoint: AutomationCheckpoint?, message: String) -> AutomationRunResult {
        let fallback = facts.creationDate == nil && rule.actions.contains {
            $0.kind == .rename && ((try? AutomationRenameTemplate($0.template).usesDate) == true)
        }
        return AutomationRunResult(details: AutomationRunDetails(ruleName: rule.name,
            finalName: working.lastPathComponent, destination: working.deletingLastPathComponent().path,
            steps: steps, dateFallback: fallback, compressionOriginalBytes: compressed, compressionSavedBytes: saved),
            outputURL: working, checkpoint: checkpoint, failed: checkpoint != nil, message: message,
            originalBytes: facts.fingerprint.size, outputBytes: (try? FileFingerprint.read(working).size) ?? facts.fingerprint.size)
    }

    private func perform(_ action: AutomationAction, working: URL, facts: AutomationFileFacts,
                         expected: FileFingerprint,
                         willPublish: @escaping @Sendable (URL) async throws -> Void) async throws -> AutomationActionOutput {
        switch action.kind {
        case .rename:
            let template = try AutomationRenameTemplate(action.template)
            let render: @Sendable (Int) throws -> String = { number in
                try template.render(originalName: facts.url.deletingPathExtension().lastPathComponent,
                    fileExtension: working.pathExtension, creationDate: facts.creationDate,
                    modificationDate: facts.modificationDate, index: number)
            }
            let name = try render(1)
            let url = try await AutomationFileOperations().transfer(source: working, to: working.deletingLastPathComponent(),
                name: name, move: true, expected: expected, collisionName: template.usesIncrement ? render : nil,
                willPublish: willPublish)
            return AutomationActionOutput(url: url, message: "Renamed", savedBytes: 0, compressedBytes: 0)
        case .move, .copy:
            guard let bookmark = action.destinationBookmark else { throw ConversionError.invalidDestination }
            let url = try await AutomationFileOperations().transfer(source: working, to: destination(bookmark),
                name: working.lastPathComponent, move: action.kind == .move, expected: expected, willPublish: willPublish)
            return AutomationActionOutput(url: url, message: action.kind == .move ? "Moved" : "Copied", savedBytes: 0, compressedBytes: 0)
        default:
            return try await AutomationMediaService().perform(action, source: working, expected: expected, willPublish: willPublish)
        }
    }

    static func destination(_ data: Data) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.isFileURL, !stale else { throw WatchError.permissionLost }
        return url
    }
    private func destination(_ data: Data) throws -> URL { try Self.destination(data) }
}

nonisolated struct AutomationActionOutput: Sendable {
    let url: URL
    let message: String
    let savedBytes: Int64
    let compressedBytes: Int64
}
