import Foundation

nonisolated enum WatcherState: Equatable { case running, paused, unavailable }

nonisolated enum OptimizationJobPhase: String, Sendable {
    case waiting = "Waiting"
    case checkingFile = "Checking file"
    case compressing = "Compressing"
    case validating = "Validating and saving"
}

nonisolated struct OptimizationJobStatus: Identifiable, Sendable {
    let id: String
    let fileName: String
    let phase: OptimizationJobPhase
}

nonisolated struct SessionStatistics: Sendable {
    var totalProcessed = 0
    var successful = 0
    var skipped = 0
    var failed = 0
    var originalBytes: Int64 = 0
    var optimizedBytes: Int64 = 0
    var bytesSaved: Int64 { max(originalBytes - optimizedBytes, 0) }

    func recording(_ result: WatchActivity) -> Self {
        var next = self
        next.totalProcessed += 1
        switch result.outcome {
        case .optimized:
            next.successful += 1
            next.originalBytes += max(result.originalBytes, 0)
            next.optimizedBytes += max(result.outputBytes, 0)
        case .skipped: next.skipped += 1
        case .failed: next.failed += 1
        }
        return next
    }
}

extension WatchedFoldersController {
    var watcherState: WatcherState {
        if paused { return .paused }
        return watchedCount == 0 && !unavailableIDs.isEmpty ? .unavailable : .running
    }
    var statusTitle: String { (paused && clipboardJobCount == 0) || outstandingJobCount == 0 ? "" : "\(outstandingJobCount)" }
    var statusSymbol: String { paused && clipboardJobCount == 0 ? "pause.fill" : "archivebox" }
    var watcherSummary: String {
        switch watcherState {
        case .paused: "Folder Watching Paused"
        case .unavailable: "Folder watcher unavailable"
        case .running: "Watching \(watchedCount) \(watchedCount == 1 ? "folder" : "folders")"
        }
    }
    var accessibilityStatus: String {
        if paused && clipboardJobCount == 0 { return "OrbitConvert folder watching paused" }
        if outstandingJobCount > 0 {
            return "OrbitConvert processing \(outstandingJobCount) \(outstandingJobCount == 1 ? "file" : "files")"
        }
        return "OrbitConvert idle. \(watcherSummary)"
    }
}
