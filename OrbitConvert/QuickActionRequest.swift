import Foundation

nonisolated struct QuickActionRequest: Codable {
    static let maximumFiles = 100
    static let maximumBytes = 8_000_000
    static let fileExtension = "orbitcompress"
    let version: Int
    let bookmarks: [Data]

    static func bookmark(for url: URL) throws -> Data {
        guard url.isFileURL else { throw RequestError.invalid }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw RequestError.invalid }
        // Ordinary bookmarks transfer temporary sandbox access between the extension and app.
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func encode(_ urls: [URL]) throws -> Data {
        guard (1...maximumFiles).contains(urls.count) else { throw RequestError.invalid }
        return try encodeBookmarks(urls.map(bookmark))
    }

    static func encodeBookmarks(_ bookmarks: [Data]) throws -> Data {
        guard (1...maximumFiles).contains(bookmarks.count),
              bookmarks.allSatisfy({ !$0.isEmpty && $0.count <= 65_536 }) else { throw RequestError.invalid }
        let data = try JSONEncoder().encode(Self(version: 1, bookmarks: bookmarks))
        guard data.count <= maximumBytes else { throw RequestError.invalid }
        return data
    }

    static func decode(_ data: Data) throws -> [URL] {
        guard data.count <= maximumBytes else { throw RequestError.invalid }
        let request = try JSONDecoder().decode(Self.self, from: data)
        guard request.version == 1, (1...maximumFiles).contains(request.bookmarks.count) else {
            throw RequestError.invalid
        }
        var urls: [URL] = []
        for bookmark in request.bookmarks {
            guard !bookmark.isEmpty, bookmark.count <= 65_536 else { throw RequestError.invalid }
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.isFileURL, !stale else { throw RequestError.invalid }
            if !urls.contains(url) { urls.append(url) }
        }
        return urls
    }

    static func read(_ url: URL) throws -> [URL] {
        guard url.isFileURL, url.pathExtension == fileExtension else { throw RequestError.invalid }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= maximumBytes else { throw RequestError.invalid }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try decode(handle.read(upToCount: maximumBytes + 1) ?? Data())
    }

    enum RequestError: LocalizedError {
        case invalid
        var errorDescription: String? {
            "This Finder selection could not be opened. Select up to 100 JPEG, PNG, or HEIC images and try again."
        }
    }
}
