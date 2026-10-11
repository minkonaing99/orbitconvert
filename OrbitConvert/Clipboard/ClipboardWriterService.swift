import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor final class ClipboardWriterService {
    let pasteboard: NSPasteboard
    private(set) var lastWrittenGeneration: Int?
    private var exports: [URL: (bytes: Int, file: URL?, resultID: UUID)] = [:]
    private var cleanupGeneration = 0
    private var preparedExports: [URL: Int] = [:]
    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func write(data: Data, type: NSPasteboard.PasteboardType, expectedGeneration: Int) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return false }
        let item = NSPasteboardItem()
        guard item.setData(data, forType: type) else { return false }
        item.setString("1", forType: .init("com.orbitconvert.optimized"))
        return write([item], expectedGeneration: expectedGeneration)
    }

    func write(_ items: [any NSPasteboardWriting], expectedGeneration: Int) -> Bool {
        defer { discard(items) }
        guard !items.isEmpty, pasteboard.changeCount == expectedGeneration else { return false }
        let originals = imageSnapshot()
        guard pasteboard.changeCount == expectedGeneration else { return false }
        let cleared = pasteboard.prepareForNewContents(with: .currentHostOnly)
        guard pasteboard.changeCount == cleared else { return false }
        if pasteboard.writeObjects(items) {
            lastWrittenGeneration = pasteboard.changeCount
            cleanupExports()
            return true
        }
        if pasteboard.changeCount == cleared, !originals.isEmpty { _ = pasteboard.writeObjects(originals) }
        lastWrittenGeneration = pasteboard.changeCount
        cleanupExports()
        return false
    }

    private func imageSnapshot() -> [any NSPasteboardWriting] {
        if pasteboard.types?.contains(.fileURL) == true {
            return pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        }
        // Read only a supported image representation, never auxiliary text/HTML or custom data providers.
        guard let first = pasteboard.pasteboardItems?.first,
              let type = [NSPasteboard.PasteboardType.png, .tiff, .init(UTType.jpeg.identifier),
                          .init(UTType.heic.identifier)].first(where: { first.types.contains($0) }),
              let data = first.data(forType: type), data.count <= 128 * 1024 * 1024 else { return [] }
        let copy = NSPasteboardItem()
        copy.setData(data, forType: type)
        return [copy]
    }

    func item(for result: ClipboardOptimizationResult) async throws -> any NSPasteboardWriting {
        if !result.fileBacked {
            let item = NSPasteboardItem()
            item.setData(result.data, forType: .init(result.typeIdentifier))
            item.setString("1", forType: .init("com.orbitconvert.optimized"))
            return item
        }
        if let existing = exports.first(where: { $0.value.resultID == result.id }),
           let file = existing.value.file {
            preparedExports[existing.key, default: 0] += 1
            return file as NSURL
        }
        guard exports.count < 64, exports.values.reduce(0, { $0 + $1.bytes }) + result.data.count <= 256 * 1024 * 1024 else {
            throw OptimizationError.cannotEncode
        }
        let directory = Self.exportRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // Reserve before suspension so concurrent Copy actions cannot exceed the bound.
        exports[directory] = (result.data.count, nil, result.id)
        preparedExports[directory] = 1
        let generation = cleanupGeneration
        do {
            let url = try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let url = directory.appendingPathComponent("Clipboard.\(result.fileExtension)")
                do { try result.data.write(to: url, options: .atomic) }
                catch { try? FileManager.default.removeItem(at: directory); throw error }
                return url
            }.value
            guard generation == cleanupGeneration else {
                try? FileManager.default.removeItem(at: directory)
                throw CancellationError()
            }
            exports[directory] = (result.data.count, url, result.id)
            return url as NSURL
        } catch {
            exports.removeValue(forKey: directory)
            preparedExports.removeValue(forKey: directory)
            throw error
        }
    }

    func exportedFile(for id: UUID) -> URL? {
        exports.values.first { $0.resultID == id }?.file
    }

    func discard(_ items: [any NSPasteboardWriting]) {
        for item in items {
            if let url = item as? NSURL {
                let directory = (url as URL).deletingLastPathComponent()
                let remaining = (preparedExports[directory] ?? 0) - 1
                if remaining <= 0 { preparedExports.removeValue(forKey: directory) }
                else { preparedExports[directory] = remaining }
            }
        }
        cleanupExports()
    }

    func cleanupExports(stopping: Bool = false) {
        if stopping { cleanupGeneration += 1 }
        let current = currentFileURLs()
        let obsolete = exports.filter { entry in
            guard let url = entry.value.file else { return false }
            return !current.contains(url) && preparedExports[entry.key] == nil
        }.map(\.key)
        for directory in obsolete { try? FileManager.default.removeItem(at: directory); exports.removeValue(forKey: directory) }
    }

    func cleanupPreviousSessions() {
        guard pasteboard.name == .general else { return }
        let current = currentFileURLs()
        let root = Self.exportRoot
        Task.detached(priority: .utility) {
            let manager = FileManager.default
            let directories = (try? manager.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .contentModificationDateKey])) ?? []
            for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil {
                guard !current.contains(where: { $0.deletingLastPathComponent() == directory }),
                      let values = try? directory.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey]),
                      values.isSymbolicLink != true, let date = values.contentModificationDate,
                      Date().timeIntervalSince(date) > 24 * 3600 else { continue }
                try? manager.removeItem(at: directory)
            }
        }
    }

    private func currentFileURLs() -> Set<URL> {
        guard pasteboard.types?.contains(.fileURL) == true else { return [] }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return Set(urls)
    }
    nonisolated private static var exportRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("OrbitConvert/ClipboardExports", isDirectory: true)
    }
}
