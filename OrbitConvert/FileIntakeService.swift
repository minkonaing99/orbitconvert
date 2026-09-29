import Foundation

struct ImportedFile: Identifiable, Sendable {
    let url: URL
    let name: String

    var id: URL { url }
}

struct FileIntakeIssue: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let message: String
}

struct FileIntakeResult: Sendable {
    let files: [ImportedFile]
    let issues: [FileIntakeIssue]
}

struct FileIntakeService: Sendable {
    nonisolated func inspect(_ urls: [URL]) -> FileIntakeResult {
        let outcomes = urls.map(inspectOne)
        return FileIntakeResult(
            files: outcomes.compactMap { if case .success(let file) = $0 { file } else { nil } },
            issues: outcomes.compactMap { if case .failure(let issue) = $0 { issue } else { nil } }
        )
    }

    nonisolated private func inspectOne(_ url: URL) -> Result<ImportedFile, FileIntakeIssue> {
        let name = url.lastPathComponent.isEmpty ? "Dropped item" : url.lastPathComponent
        guard url.isFileURL else {
            return .failure(FileIntakeIssue(name: name, message: "Only local files can be imported."))
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                return .failure(FileIntakeIssue(name: name, message: "Choose a file, not a folder."))
            }
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                return .failure(FileIntakeIssue(name: name, message: "This file cannot be read."))
            }
            return .success(ImportedFile(url: url, name: name))
        } catch {
            return .failure(FileIntakeIssue(name: name, message: "This file is unavailable or cannot be read."))
        }
    }
}

extension FileIntakeIssue: Error {}
