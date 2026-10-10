import AppKit
import UniformTypeIdentifiers

final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        Task { @MainActor in
            do {
                let attachments = context.inputItems.compactMap { $0 as? NSExtensionItem }
                    .flatMap { $0.attachments ?? [] }
                guard (1...QuickActionRequest.maximumFiles).contains(attachments.count) else {
                    throw QuickActionRequest.RequestError.invalid
                }
                var bookmarks: [Data] = []
                for attachment in attachments {
                    bookmarks.append(try await bookmark(from: attachment))
                }
                let request = try writeRequest(QuickActionRequest.encodeBookmarks(bookmarks))
                let app = Bundle.main.bundleURL.deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                guard app.pathExtension == "app" else { throw QuickActionRequest.RequestError.invalid }
                try await open(request, with: app)
                // Finder treats omitted input attachments as deletions. Return every original unchanged.
                context.completeRequest(returningItems: context.inputItems)
            } catch {
                context.cancelRequest(withError: error)
            }
        }
    }

    private func bookmark(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, inPlace, error in
                do {
                    if let error { throw error }
                    guard inPlace, let url else { throw QuickActionRequest.RequestError.invalid }
                    continuation.resume(returning: try QuickActionRequest.bookmark(for: url))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func writeRequest(_ data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitConvertRequests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let previous = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])) ?? []
        for url in previous where url.pathExtension == QuickActionRequest.fileExtension {
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
               values.isRegularFile == true, let modified = values.contentModificationDate,
               modified < Date().addingTimeInterval(-86_400) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(QuickActionRequest.fileExtension)
        try data.write(to: url, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        // Launch completion does not prove the app has read the document; let a later invocation age it out.
        return url
    }

    @MainActor private func open(_ request: URL, with app: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([request], withApplicationAt: app,
                configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
