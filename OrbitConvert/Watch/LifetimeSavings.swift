import Foundation

nonisolated struct LifetimeSavings: Equatable, Sendable {
    static let bytesKey = "lifetimeSavedBytes"
    static let filesKey = "lifetimeOptimizedCount"
    static let didChange = Notification.Name("OrbitConvert.lifetimeSavingsDidChange")

    var bytes: Int64 = 0
    var files = 0

    var summary: String {
        "Total saved: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) across \(files) \(files == 1 ? "file" : "files")"
    }

    func adding(_ saved: Int64) -> Self {
        guard saved > 0 else { return self }
        let (sum, overflow) = bytes.addingReportingOverflow(saved)
        return Self(bytes: overflow ? .max : sum, files: files == .max ? .max : files + 1)
    }

    // The first load after this feature ships starts from the saved history instead of zero.
    static func load(from defaults: UserDefaults, seedingFrom history: [WatchActivity]) -> Self {
        guard defaults.object(forKey: bytesKey) != nil else {
            let seeded = history.reduce(Self()) { $0.adding($1.savingsBytes) }
            seeded.save(to: defaults)
            return seeded
        }
        let bytes = max((defaults.object(forKey: bytesKey) as? NSNumber)?.int64Value ?? 0, 0)
        return Self(bytes: bytes, files: max(defaults.integer(forKey: filesKey), 0))
    }

    func save(to defaults: UserDefaults) {
        defaults.set(NSNumber(value: bytes), forKey: Self.bytesKey)
        defaults.set(files, forKey: Self.filesKey)
    }

    // Manual results (main window, Finder Quick Action) are added here; the watch controller refreshes on the notification.
    static func record(_ results: [CompressionResult], in defaults: UserDefaults = .standard) {
        let current = load(from: defaults, seedingFrom: [])
        let next = results.reduce(current) { $0.adding($1.savingsBytes) }
        guard next != current else { return }
        next.save(to: defaults)
        NotificationCenter.default.post(name: didChange, object: defaults)
    }
}
