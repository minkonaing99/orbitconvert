import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct SafeFileReplacementService: Sendable {
    nonisolated init() {}

    nonisolated func replace(source: URL, candidate: URL, expected: FileFingerprint,
                             trashOriginal: Bool = false,
                             postReplacementCheck: @Sendable (URL) -> Bool = { _ in true }) throws -> URL {
        guard try FileFingerprint.read(source).matches(expected) else { throw WatchError.sourceChanged }
        let type = try contentType(source)
        guard try isValid(candidate, as: type),
              try FileFingerprint.read(candidate).size < expected.size else {
            throw WatchError.invalidCandidate
        }
        let parent = source.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".orbitconvert-replace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: candidate, to: staged)
        guard try isValid(staged, as: type),
              try FileFingerprint.read(staged).size < expected.size else { throw WatchError.invalidCandidate }
        try Task.checkCancellation()
        guard try FileFingerprint.read(source).matches(expected) else { throw WatchError.sourceChanged }

        let backupName = ".orbitconvert-backup-\(UUID().uuidString)"
        let backup = parent.appendingPathComponent(backupName)
        do {
            let replaced = try FileManager.default.replaceItemAt(
                source, withItemAt: staged, backupItemName: backupName,
                options: [.withoutDeletingBackupItem]
            ) ?? source
            guard postReplacementCheck(replaced), try isValid(replaced, as: type),
                  try FileFingerprint.read(replaced).size < expected.size else {
                throw WatchError.invalidCandidate
            }
            if trashOriginal {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: backup, resultingItemURL: &trashed)
            } else {
                try? FileManager.default.removeItem(at: backup)
            }
            return replaced
        } catch {
            if FileManager.default.fileExists(atPath: backup.path) {
                guard restoreBackup(backup, to: source, expected: expected) else {
                    throw WatchError.recoveryRequired(backupName)
                }
            } else if !FileManager.default.fileExists(atPath: source.path) {
                throw WatchError.recoveryRequired(backupName)
            }
            throw error
        }
    }

    nonisolated func keepBoth(source: URL, candidate: URL, expected: FileFingerprint) throws -> URL {
        guard try FileFingerprint.read(source).matches(expected),
              try isValid(candidate, as: contentType(source)),
              try FileFingerprint.read(candidate).size < expected.size else { throw WatchError.invalidCandidate }
        let parent = source.deletingLastPathComponent()
        let temporary = try FileOutputService().makeTemporaryFile(in: parent)
        defer { FileOutputService().removeTemporaryFile(temporary) }
        try FileManager.default.copyItem(at: candidate, to: temporary)
        guard try FileFingerprint.read(source).matches(expected) else { throw WatchError.sourceChanged }
        return try FileOutputService().publish(temporary,
                                               stem: source.deletingPathExtension().lastPathComponent + "-optimized",
                                               fileExtension: source.pathExtension, in: parent)
    }

    nonisolated private func contentType(_ url: URL) throws -> WatchFileType {
        if url.pathExtension.lowercased() == "pdf", PDFDocument(url: url)?.pageCount ?? 0 > 0 {
            return .pdf
        }
        guard let image = CGImageSourceCreateWithURL(url as CFURL, nil),
              let identifier = CGImageSourceGetType(image) as String?,
              let type = WatchFileType.actualType(identifier) else { throw WatchError.invalidCandidate }
        return type
    }

    nonisolated private func isValid(_ url: URL, as type: WatchFileType) throws -> Bool {
        let candidate = try FileFingerprint.read(url)
        guard candidate.size > 0 else { return false }
        if type == .pdf {
            return PDFDocument(url: url)?.pageCount ?? 0 > 0
        }
        guard let image = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(image) == 1,
              CGImageSourceGetStatusAtIndex(image, 0) == .statusComplete,
              let identifier = CGImageSourceGetType(image) as String?,
              WatchFileType.actualType(identifier) == type else { return false }
        return CGImageSourceCreateImageAtIndex(image, 0, nil) != nil
    }

    nonisolated private func restoreBackup(_ backup: URL, to source: URL,
                                            expected: FileFingerprint) -> Bool {
        guard FileManager.default.fileExists(atPath: backup.path) else { return false }
        if !FileManager.default.fileExists(atPath: source.path) {
            do {
                try FileManager.default.moveItem(at: backup, to: source)
                return (try? FileFingerprint.read(source).size) == expected.size
            } catch { return false }
        }
        let recovery = backup.deletingLastPathComponent()
            .appendingPathComponent(".orbitconvert-recovery-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: backup, to: recovery)
            defer { try? FileManager.default.removeItem(at: recovery) }
            let failedName = ".orbitconvert-failed-\(UUID().uuidString)"
            _ = try FileManager.default.replaceItemAt(source, withItemAt: recovery,
                                                      backupItemName: failedName,
                                                      options: [.withoutDeletingBackupItem])
            guard try FileFingerprint.read(source).size == expected.size else { return false }
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.removeItem(at: source.deletingLastPathComponent()
                .appendingPathComponent(failedName))
            return true
        } catch {
            // Keep the original backup for manual recovery if the rollback itself fails.
            return false
        }
    }
}
