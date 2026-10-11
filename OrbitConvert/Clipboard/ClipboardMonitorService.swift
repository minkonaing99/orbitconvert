import AppKit
import Observation
import UniformTypeIdentifiers

@Observable @MainActor final class ClipboardMonitorService {
    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "clipboardEnabled")
            if !enabled {
                lifecycleGeneration += 1
                cancelPending?()
                poller?.cancel(); poller = nil
            } else if submit != nil {
                observedGeneration = writer.pasteboard.changeCount
                beginPolling()
            }
        }
    }
    var optimizeImages: Bool { didSet { defaults.set(optimizeImages, forKey: "clipboardImages") } }
    var optimizeFiles: Bool { didSet { defaults.set(optimizeFiles, forKey: "clipboardFiles") } }
    var showResults: Bool { didSet { defaults.set(showResults, forKey: "clipboardShowResults") } }
    var collectResults: Bool { didSet { defaults.set(collectResults, forKey: "clipboardCollect"); if !collectResults { results = [] } } }
    var preset: CompressionPreset { didSet { defaults.set(preset.rawValue, forKey: "clipboardPreset") } }
    var ignoredApps: [String] { didSet { defaults.set(ignoredApps, forKey: "clipboardIgnoredApps") } }
    private(set) var results: [ClipboardOptimizationResult] = []
    private(set) var lastResult: ClipboardOptimizationResult?
    var message: String?
    @ObservationIgnored private let optimizer: @Sendable (ClipboardItem, CompressionPreset, ClipboardFingerprintRegistry) throws -> ClipboardOptimizationResult?
    @ObservationIgnored private var lifecycleGeneration = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let writer: ClipboardWriterService
    @ObservationIgnored private var observedGeneration: Int
    @ObservationIgnored private var registry = ClipboardFingerprintRegistry()
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var submit: ((@escaping @MainActor () async -> WatchActivity?) -> Void)?
    @ObservationIgnored private var cancelPending: (() -> Void)?
    @ObservationIgnored private var resultPanel: ClipboardResultPanel?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general,
         optimizer: @escaping @Sendable (ClipboardItem, CompressionPreset, ClipboardFingerprintRegistry) throws -> ClipboardOptimizationResult? = { item, preset, registry in
             try ClipboardOptimizationService().optimize(item, preset: preset) { registry.contains($0) }
         }) {
        self.optimizer = optimizer
        self.defaults = defaults
        writer = ClipboardWriterService(pasteboard: pasteboard)
        observedGeneration = pasteboard.changeCount
        enabled = defaults.object(forKey: "clipboardEnabled") as? Bool ?? true
        optimizeImages = defaults.object(forKey: "clipboardImages") as? Bool ?? true
        optimizeFiles = defaults.object(forKey: "clipboardFiles") as? Bool ?? true
        showResults = defaults.object(forKey: "clipboardShowResults") as? Bool ?? true
        collectResults = defaults.bool(forKey: "clipboardCollect")
        preset = CompressionPreset(rawValue: defaults.string(forKey: "clipboardPreset") ?? "") ?? .balanced
        ignoredApps = defaults.stringArray(forKey: "clipboardIgnoredApps") ?? []
    }

    func start(submit: @escaping (@escaping @MainActor () async -> WatchActivity?) -> Void,
               cancelPending: @escaping () -> Void) {
        guard self.submit == nil else { return }
        self.submit = submit
        self.cancelPending = cancelPending
        observedGeneration = writer.pasteboard.changeCount
        if enabled { writer.cleanupPreviousSessions(); beginPolling() }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
    }

    private func beginPolling() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { break }
                self?.checkClipboard()
            }
        }
    }

    func stop() {
        lifecycleGeneration += 1
        poller?.cancel(); poller = nil
        cancelPending?()
        submit = nil; cancelPending = nil
        writer.cleanupExports(stopping: true)
        results = []; lastResult = nil
        resultPanel?.close(); resultPanel = nil
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
    }

    func checkClipboard(frontmostBundleID: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
        guard enabled else { return }
        let board = writer.pasteboard
        let generation = board.changeCount
        guard generation != observedGeneration else { return }
        observedGeneration = generation
        writer.cleanupExports()
        cancelPending?()
        guard enabled, generation != writer.lastWrittenGeneration,
              !isIgnored(frontmostBundleID),
              let items = board.pasteboardItems, items.count == 1,
              let first = items.first, let type = ClipboardItem.preferredType(first.types) else { return }
        let item: ClipboardItem
        if type == .fileURL {
            guard optimizeFiles,
                  let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  urls.count == 1, let url = urls.first, url.isFileURL,
                  let declared = UTType(filenameExtension: url.pathExtension),
                  [UTType.png, .jpeg, .tiff, .heic].contains(where: { declared.conforms(to: $0) }) else { return }
            item = ClipboardItem(generation: generation, data: nil, fileURL: url, typeIdentifier: declared.identifier)
        } else {
            guard optimizeImages, let data = first.data(forType: type),
                  data.count <= 128 * 1024 * 1024 else { return }
            item = ClipboardItem(generation: generation, data: data, fileURL: nil, typeIdentifier: type.rawValue)
        }
        guard board.changeCount == generation else { return }
        submit? { [weak self] in await self?.process(item) }
    }

    func isIgnored(_ bundleID: String?) -> Bool {
        bundleID.map { ignoredApps.contains($0) } ?? false
    }

    func process(_ item: ClipboardItem) async -> WatchActivity? {
        guard enabled, writer.pasteboard.changeCount == item.generation else { return nil }
        let known = registry
        let mode = preset
        let lifecycle = lifecycleGeneration
        let optimize = optimizer
        do {
            let result = try await Task.detached(priority: .utility) {
                try optimize(item, mode, known)
            }.value
            guard lifecycle == lifecycleGeneration else { return nil }
            guard let result else {
                return WatchActivity(fileName: "Clipboard image", outcome: .skipped,
                    message: mode == .lossless ? "No lossless reduction available" : "Already optimized or no useful reduction")
            }
            registry.insert(result.sourceFingerprint)
            registry.insert(result.outputFingerprint)
            let stillCurrent = enabled && writer.pasteboard.changeCount == item.generation
            var written = false
            if stillCurrent {
                let output = try await writer.item(for: result)
                if enabled && lifecycle == lifecycleGeneration {
                    written = writer.write([output], expectedGeneration: item.generation)
                } else { writer.discard([output]) }
            }
            writer.cleanupExports()
            if collectResults { retain(result) }
            if written {
                lastResult = result
                if showResults { show(result) }
            }
            return WatchActivity(fileName: "Clipboard image", outcome: written ? .optimized : .skipped,
                originalBytes: result.originalBytes, outputBytes: Int64(result.data.count),
                message: written ? "Clipboard optimized" : "Newer clipboard kept; result not applied")
        } catch {
            return WatchActivity(fileName: "Clipboard image", outcome: .failed,
                                 message: "Could not optimize image. Clipboard unchanged.")
        }
    }

    private func retain(_ result: ClipboardOptimizationResult) {
        var next = Array((results + [result]).suffix(20))
        while next.reduce(0, { $0 + $1.data.count }) > 128 * 1024 * 1024 { next.removeFirst() }
        results = next
    }

    func clearResults() { results = []; lastResult = nil; resultPanel?.close(); resultPanel = nil }

    func copy(_ values: [ClipboardOptimizationResult]) {
        let generation = writer.pasteboard.changeCount
        Task {
            var items: [any NSPasteboardWriting] = []
            defer { writer.discard(items) }
            do {
                for result in values { items.append(try await writer.item(for: result)) }
                if !writer.write(items, expectedGeneration: generation) { message = "Clipboard changed or results could not be copied." }
                items = []
                writer.cleanupExports()
            } catch { message = "Could not prepare clipboard results." }
        }
    }

    func save(_ values: [ClipboardOptimizationResult]) {
        guard !values.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in
                do {
                    try await Task.detached(priority: .utility) {
                        let scoped = folder.startAccessingSecurityScopedResource()
                        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
                        for result in values {
                            let service = FileOutputService()
                            let temporary = try service.makeTemporaryFile(in: folder)
                            defer { service.removeTemporaryFile(temporary) }
                            try result.data.write(to: temporary)
                            _ = try service.publish(temporary, stem: "Clipboard",
                                                    fileExtension: result.fileExtension, in: folder)
                        }
                    }.value
                } catch { self?.message = "Could not save clipboard results." }
            }
        }
    }

    private func show(_ result: ClipboardOptimizationResult) {
        resultPanel?.close()
        resultPanel = ClipboardResultPanel(result: result, copy: { [weak self] in self?.copy([result]) },
            save: { [weak self] in self?.save([result]) }, reveal: { [weak self] in
                guard let self else { return }
                if let url = self.writer.exportedFile(for: result.id) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else { self.message = "Temporary copy expired. Use Save to keep a copy." }
            }, onClose: { [weak self] in self?.lastResult = nil; self?.resultPanel = nil })
        resultPanel?.show()
    }
}
