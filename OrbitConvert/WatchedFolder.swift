import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum WatchFileType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case jpeg, png, heic, pdf

    nonisolated var id: String { rawValue }
    nonisolated var label: String { rawValue.uppercased() == "JPEG" ? "JPEG" : rawValue.uppercased() }
    nonisolated var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .pdf: .pdf
        }
    }

    nonisolated var isAvailable: Bool {
        self != .heic || Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
            .contains(UTType.heic.identifier)
    }

    nonisolated static func actualType(_ identifier: String) -> Self? {
        guard let type = UTType(identifier) else { return nil }
        return allCases.first { type.conforms(to: $0.type) }
    }
}

nonisolated enum ReplacementBehavior: String, CaseIterable, Codable, Identifiable, Sendable {
    case replaceOriginal, moveOriginalToTrash, keepBoth

    nonisolated var id: String { rawValue }
    nonisolated var label: String {
        switch self {
        case .replaceOriginal: "Replace Original"
        case .moveOriginalToTrash: "Move Original to Trash"
        case .keepBoth: "Keep Both"
        }
    }
}

nonisolated struct WatchedFolder: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var bookmarkData: Data
    var isEnabled: Bool
    var watchSubdirectories: Bool
    var preset: CompressionPreset
    var supportedTypes: Set<WatchFileType>
    var replacementBehavior: ReplacementBehavior

    nonisolated init(id: UUID = UUID(), displayName: String, bookmarkData: Data,
                     isEnabled: Bool = true, watchSubdirectories: Bool = false,
                     preset: CompressionPreset = .balanced,
                     supportedTypes: Set<WatchFileType>? = nil,
                     replacementBehavior: ReplacementBehavior = .replaceOriginal) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.isEnabled = isEnabled
        self.watchSubdirectories = watchSubdirectories
        self.preset = preset
        self.supportedTypes = supportedTypes ?? Set(WatchFileType.allCases.filter(\.isAvailable))
        self.replacementBehavior = replacementBehavior
    }
}

enum WatchFilePolicy {
    nonisolated static func isEligibleName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("."),
              !name.lowercased().hasPrefix("orbitconvert-") else { return false }
        let suffix = "." + (name as NSString).pathExtension.lowercased()
        return ![".crdownload", ".download", ".part", ".tmp", ".temp", ".partial", ".filepart"]
            .contains(suffix)
    }

    nonisolated static func isEligibleFile(_ url: URL, allowed: Set<WatchFileType>) -> Bool {
        guard isEligibleName(url.lastPathComponent),
              let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey, .contentTypeKey
              ]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return false }
        if values.isUbiquitousItem == true,
           values.ubiquitousItemDownloadingStatus != .current { return false }
        guard let type = values.contentType,
              let watchType = WatchFileType.actualType(type.identifier) else { return false }
        return watchType.isAvailable && allowed.contains(watchType)
    }
}

nonisolated struct FileFingerprint: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    nonisolated static func read(_ url: URL) throws -> Self {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw WatchError.unavailableFile
        }
        return Self(device: UInt64(info.st_dev), inode: UInt64(info.st_ino),
                    size: info.st_size, modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
                    modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                    changedSeconds: Int64(info.st_ctimespec.tv_sec),
                    changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }

    nonisolated func matches(_ other: Self) -> Bool {
        device == other.device && inode == other.inode && size == other.size &&
            modifiedSeconds == other.modifiedSeconds && modifiedNanoseconds == other.modifiedNanoseconds &&
            changedSeconds == other.changedSeconds && changedNanoseconds == other.changedNanoseconds
    }

    nonisolated func changed(afterSeconds seconds: Int64, nanoseconds: Int64) -> Bool {
        changedSeconds > seconds || (changedSeconds == seconds && changedNanoseconds > nanoseconds)
    }
}

nonisolated enum WatchError: Error, LocalizedError, Equatable, Sendable {
    case unavailableFile, unstableFile, sourceChanged, invalidCandidate, noReduction, permissionLost
    case recoveryRequired(String)

    var errorDescription: String? {
        switch self {
        case .unavailableFile: "File is unavailable or is not a regular file."
        case .unstableFile: "File is still being written."
        case .sourceChanged: "File changed while optimization was running; original kept."
        case .invalidCandidate: "Optimized output is invalid; original kept."
        case .noReduction: "Optimization would not reduce file size."
        case .permissionLost: "Folder access expired. Grant access again in Settings."
        case .recoveryRequired(let name): "Original may need recovery from \(name) beside the file."
        }
    }
}
