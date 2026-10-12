import Foundation
import UniformTypeIdentifiers

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
    nonisolated static let folderLimit = 500
    nonisolated private static let supportedTypes: [UTType] = [.png, .jpeg, .heic, .heif, .tiff, .pdf]

    nonisolated func inspect(_ urls: [URL]) -> FileIntakeResult {
        var files: [ImportedFile] = []
        var issues: [FileIntakeIssue] = []
        var seen = Set<URL>()
        for outcome in urls.flatMap(outcomes) {
            switch outcome {
            case .success(let file):
                if seen.insert(file.url.standardizedFileURL).inserted { files.append(file) }
            case .failure(let issue): issues.append(issue)
            }
        }
        return FileIntakeResult(files: files, issues: issues)
    }

    nonisolated private func outcomes(for url: URL) -> [Result<ImportedFile, FileIntakeIssue>] {
        isFolder(url) ? expandFolder(url) : [inspectOne(url)]
    }

    nonisolated private func isFolder(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    // Top level only; skips the same hidden, temporary, symlinked and not-downloaded files as watched folders.
    // Folder access is intentionally kept for the session: the files inside have no scope of their own and are
    // read again later by inspection and actions.
    nonisolated private func expandFolder(_ folder: URL) -> [Result<ImportedFile, FileIntakeIssue>] {
        let name = folder.lastPathComponent
        _ = folder.startAccessingSecurityScopedResource()
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return [.failure(FileIntakeIssue(name: name, message: "This folder cannot be read."))]
        }
        let supported = contents.filter { isSupported($0) && WatchFilePolicy.isEligibleFile($0, allowed: nil) }
            .sorted(by: Self.nameOrder)
        guard !supported.isEmpty else {
            return [.failure(FileIntakeIssue(name: name, message: "This folder has no supported images, PDFs or Markdown files."))]
        }
        var results: [Result<ImportedFile, FileIntakeIssue>] = supported.prefix(Self.folderLimit).map {
            .success(ImportedFile(url: $0, name: $0.lastPathComponent))
        }
        if supported.count > Self.folderLimit {
            results.append(.failure(FileIntakeIssue(name: name,
                message: "This folder has \(supported.count) supported files; the first \(Self.folderLimit) were added.")))
        }
        return results
    }

    nonisolated private static func nameOrder(_ left: URL, _ right: URL) -> Bool {
        switch left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: left.lastPathComponent < right.lastPathComponent
        }
    }

    nonisolated private func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["md", "markdown"].contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return Self.supportedTypes.contains { type.conforms(to: $0) }
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
