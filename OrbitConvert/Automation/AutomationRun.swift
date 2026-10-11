import Foundation

nonisolated struct AutomationStepRecord: Identifiable, Codable, Sendable {
    var id = UUID()
    let action: String
    let inputName: String
    let outputName: String
    let destination: String
    let message: String
    let failed: Bool
    var savedBytes: Int64 = 0
}

nonisolated struct AutomationRunDetails: Codable, Sendable {
    let ruleName: String
    let finalName: String
    let destination: String
    let steps: [AutomationStepRecord]
    let dateFallback: Bool
    let compressionOriginalBytes: Int64
    let compressionSavedBytes: Int64
}

nonisolated struct AutomationCheckpoint: Sendable {
    let original: AutomationFileFacts
    let rule: AutomationRule
    let workingURL: URL
    let expected: FileFingerprint
    let nextAction: Int
    let steps: [AutomationStepRecord]
    let compressedBytes: Int64
    let savedBytes: Int64
    let cleanupOutput: URL?
    let cleanupExpected: FileFingerprint?
}

nonisolated struct AutomationRunResult: Sendable {
    let details: AutomationRunDetails
    let outputURL: URL?
    let checkpoint: AutomationCheckpoint?
    let failed: Bool
    let message: String
    let originalBytes: Int64
    let outputBytes: Int64
}
