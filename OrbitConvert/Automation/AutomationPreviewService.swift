import Foundation

nonisolated struct AutomationPreviewItem: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let rule: AutomationRule?
    let fingerprint: FileFingerprint?
    let summary: String
    let issue: String?
}

nonisolated enum AutomationPreviewService {
    static func preview(folder: WatchedFolder, rule: AutomationRule? = nil) async throws -> [AutomationPreviewItem] {
        try await Task.detached(priority: .utility) {
            let root = try AutomationExecutionService.destination(folder.bookmarkData)
            let scoped = root.startAccessingSecurityScopedResource()
            defer { if scoped { root.stopAccessingSecurityScopedResource() } }
            let rules = rule.map { [$0] } ?? folder.effectiveRules
            for rule in rules { try rule.validate() }
            let urls = WatchedFoldersController.scan(root, recursive: rules.contains { $0.includeSubfolders }, allowed: nil)
            var reserved: Set<URL> = []
            return try urls.sorted { $0.path < $1.path }.map { url in
                try Task.checkCancellation()
                do {
                    let facts = try AutomationFileFacts.read(url, includeText: rules.contains { $0.conditions.contains { $0.field == .text } })
                    let matched = try AutomationConditionService.firstMatch(rules, facts: facts,
                        isSubfolder: url.deletingLastPathComponent().standardizedFileURL != root.standardizedFileURL)
                    let summary = try matched.map { try projection($0, facts: facts, reserved: &reserved) } ?? "No matching rule"
                    return AutomationPreviewItem(url: url, rule: matched, fingerprint: facts.fingerprint,
                        summary: summary, issue: matched == nil ? facts.textIssue : nil)
                } catch {
                    return AutomationPreviewItem(url: url, rule: nil, fingerprint: try? FileFingerprint.read(url),
                        summary: "File could not be previewed", issue: error.localizedDescription)
                }
            }
        }.value
    }

    private static func projection(_ rule: AutomationRule, facts: AutomationFileFacts,
                                   reserved: inout Set<URL>) throws -> String {
        var working = facts.url
        var format = ConversionFormat.sourceFormat(for: facts.typeIdentifier)?.rawValue ?? (facts.category == "PDF" ? "pdf" : "other")
        var descriptions: [String] = []
        for action in rule.actions {
            let directory: URL
            let name: String
            var increment: ((Int) throws -> String)?
            switch action.kind {
            case .rename:
                let template = try AutomationRenameTemplate(action.template)
                let ext = working.pathExtension
                let render: (Int) throws -> String = { index in
                    try template.render(originalName: facts.url.deletingPathExtension().lastPathComponent,
                        fileExtension: ext, creationDate: facts.creationDate,
                        modificationDate: facts.modificationDate, index: index)
                }
                directory = working.deletingLastPathComponent()
                name = try render(1)
                increment = template.usesIncrement ? render : nil
            case .move, .copy:
                guard let data = action.destinationBookmark else { throw ConversionError.invalidDestination }
                directory = try AutomationExecutionService.destination(data)
                name = working.lastPathComponent
            default:
                let supported = action.kind == .convert || action.kind == .removeMetadata
                    ? ["jpeg", "png", "heic", "tiff"] + (action.kind == .removeMetadata ? ["pdf"] : [])
                    : ["jpeg", "png", "heic"] + (action.kind == .compress ? ["pdf"] : [])
                guard supported.contains(format) else {
                    throw AutomationError.invalid(action.kind.rawValue + " does not support this file type.")
                }
                if action.kind == .compress, action.preset == .lossless, ["jpeg", "heic"].contains(format) {
                    throw AutomationError.invalid("Lossless compression is unavailable for JPEG and HEIC.")
                }
                directory = working.deletingLastPathComponent()
                let stem = working.deletingPathExtension().lastPathComponent
                let ext = working.pathExtension
                switch action.kind {
                case .convert:
                    format = action.format
                    name = stem + "." + (action.format == "jpeg" ? "jpg" : action.format)
                case .resize: name = stem + "-resized." + ext
                case .removeMetadata: name = ext.lowercased() == "pdf" ? stem + "-clean.pdf" : working.lastPathComponent
                case .compress:
                    if action.replacement != .keepBoth {
                        descriptions.append("Compress: replace only if smaller and valid")
                        continue
                    }
                    name = stem + "-optimized" + (ext.isEmpty ? "" : "." + ext)
                default: name = working.lastPathComponent
                }
                descriptions.append(action.kind.rawValue + " (provisional output; checked when run)")
            }
            let scoped = directory.startAccessingSecurityScopedResource()
            defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw ConversionError.invalidDestination
            }
            var candidate = directory.appendingPathComponent(name)
            var suffix = 0
            while reserved.contains(candidate) || (FileManager.default.fileExists(atPath: candidate.path) &&
                (![.rename, .move].contains(action.kind) || candidate.standardizedFileURL != working.standardizedFileURL)) {
                suffix += 1
                guard suffix < 10_000 else { throw AutomationError.invalid("Too many files share this name.") }
                let base = URL(fileURLWithPath: name)
                let ext = base.pathExtension.isEmpty ? "" : "." + base.pathExtension
                candidate = directory.appendingPathComponent(try increment?(suffix + 1) ??
                    base.deletingPathExtension().lastPathComponent + "-\(suffix)" + ext)
            }
            reserved.insert(candidate)
            working = candidate
            descriptions.append("\(action.kind.rawValue): \(candidate.path)")
        }
        return descriptions.joined(separator: "\n")
    }
}
