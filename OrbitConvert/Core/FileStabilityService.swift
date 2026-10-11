import Foundation

struct FileStabilityService: Sendable {
    nonisolated init() {}

    nonisolated func waitUntilStable(_ url: URL, interval: Duration = .seconds(1),
                                     maximumChecks: Int = 60) async throws -> FileFingerprint {
        var previous: FileFingerprint?
        var unchanged = 0
        for _ in 0..<maximumChecks {
            try Task.checkCancellation()
            let current = try FileFingerprint.read(url)
            if current.size > 0 && previous?.matches(current) == true {
                unchanged += 1
                if unchanged >= 2 {
                    let handle = try FileHandle(forReadingFrom: url)
                    try handle.close()
                    return current
                }
            } else {
                unchanged = 0
            }
            previous = current
            try await Task.sleep(for: interval)
        }
        throw WatchError.unstableFile
    }
}
