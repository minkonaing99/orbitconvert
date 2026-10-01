import AppKit
import CoreServices
import Foundation
import Observation
import OSLog

@Observable @MainActor
final class WatchedFoldersController {
    let clipboard: ClipboardMonitorService
    @ObservationIgnored private let clipboardOwnerID = UUID()
    @ObservationIgnored private var clipboardWork: [URL: @MainActor () async -> WatchActivity?] = [:]
    private var activeIsClipboard = false
    var folders: [WatchedFolder] = []
    var activity: [WatchActivity] = []
    private(set) var sessionStatistics = SessionStatistics()
    private var activePhase = OptimizationJobPhase.checkingFile
    var paused = false
    var currentFileName: String?
    var unavailableIDs: Set<UUID> = []

    @ObservationIgnored private let defaults: UserDefaults
    private var running: [UUID: RunningWatch] = [:]
    @ObservationIgnored private var starting: [UUID: (URL, Task<Void, Never>)] = [:]
    @ObservationIgnored private var optimizeOnStart: Set<UUID> = []
    private var pending: [(URL, UUID, Int, Date)] = []
    @ObservationIgnored private var queuedURLs: Set<URL> = []
    private var activeURL: URL?
    @ObservationIgnored private var activeFolderID: UUID?
    @ObservationIgnored private var activeTask: Task<WatchJobResult, Never>?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var recent: [URL: (FileFingerprint, Date)] = [:]
    @ObservationIgnored private var retryOnChange: [URL: FileFingerprint] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "com.example.OrbitConvert", category: "FolderWatch")

    private final class RunningWatch {
        let token: UUID
        let url: URL
        let watcher: FolderWatchService
        let replayThroughID: FSEventStreamEventId
        let startedSeconds: Int64
        let startedNanoseconds: Int64
        var known: Set<URL>
        var debounce: Task<Void, Never>?

        init(token: UUID, url: URL, watcher: FolderWatchService,
             replayThroughID: FSEventStreamEventId,
             startedSeconds: Int64, startedNanoseconds: Int64,
             known: Set<URL>) {
            self.token = token
            self.url = url
            self.watcher = watcher
            self.replayThroughID = replayThroughID
            self.startedSeconds = startedSeconds
            self.startedNanoseconds = startedNanoseconds
            self.known = known
        }

        func stop() {
            debounce?.cancel()
            watcher.stop()
            url.stopAccessingSecurityScopedResource()
        }
    }

    init(defaults: UserDefaults = .standard, startClipboard: Bool = false) {
        self.defaults = defaults
        clipboard = ClipboardMonitorService(defaults: defaults)
        if let data = defaults.data(forKey: "watchedFolders"),
           let stored = try? JSONDecoder().decode([WatchedFolder].self, from: data) {
            folders = stored
        }
        if let data = defaults.data(forKey: "watchedActivity"),
           let stored = try? JSONDecoder().decode([WatchActivity].self, from: data) {
            activity = stored
        }
        paused = defaults.bool(forKey: "watchingPaused")
        if !paused { for folder in folders where folder.isEnabled { start(folder) } }
        if startClipboard {
            clipboard.start(submit: { [weak self] operation in self?.enqueueClipboard(operation) },
                            cancelPending: { [weak self] in self?.cancelPendingClipboard() })
        }
    }

    var watchedCount: Int { running.count }
    var activeJobs: [OptimizationJobStatus] {
        activeURL.map { [OptimizationJobStatus(id: $0.absoluteString, fileName: activeIsClipboard ? "Clipboard image" : $0.lastPathComponent,
                                               phase: activePhase)] } ?? []
    }
    var queuedJobs: [OptimizationJobStatus] {
        pending.map { OptimizationJobStatus(id: $0.0.absoluteString,
                                           fileName: $0.1 == clipboardOwnerID ? "Clipboard image" : $0.0.lastPathComponent, phase: .waiting) }
    }
    var outstandingJobCount: Int { activeJobs.count + queuedJobs.count }
    var queuedCount: Int { outstandingJobCount }
    var clipboardJobCount: Int { pending.filter { $0.1 == clipboardOwnerID }.count + (activeIsClipboard ? 1 : 0) }

    func enqueueClipboard(_ operation: @escaping @MainActor () async -> WatchActivity?) {
        cancelPendingClipboard()
        let key = URL(fileURLWithPath: "/clipboard-job/" + UUID().uuidString)
        clipboardWork[key] = operation
        pending.append((key, clipboardOwnerID, 0, Date()))
        if worker == nil { worker = Task { await drain() } }
    }

    func cancelPendingClipboard() {
        let keys = Set(pending.filter { $0.1 == clipboardOwnerID }.map(\.0))
        pending = pending.filter { $0.1 != clipboardOwnerID }
        clipboardWork = clipboardWork.filter { !keys.contains($0.key) }
    }

    private func runClipboard(_ url: URL) async {
        guard let operation = clipboardWork.removeValue(forKey: url) else { return }
        activeURL = url
        activeIsClipboard = true
        activePhase = .compressing
        currentFileName = "Clipboard image"
        if let result = await operation() { record(result) }
        activeIsClipboard = false
        activeURL = nil
        currentFileName = nil
    }

    private func record(_ result: WatchActivity) {
        sessionStatistics = sessionStatistics.recording(result)
        activity = Array(([result] + activity).prefix(200))
        if let data = try? JSONEncoder().encode(activity) { defaults.set(data, forKey: "watchedActivity") }
    }

    func add(_ urls: [URL], optimizeExisting: Bool) throws {
        for url in urls {
            guard url.isFileURL,
                  try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw WatchError.unavailableFile
            }
            if folders.contains(where: { (try? resolve($0).url.standardizedFileURL) == url.standardizedFileURL }) {
                continue
            }
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            let folder = WatchedFolder(displayName: url.lastPathComponent, bookmarkData: bookmark)
            folders = folders + [folder]
            saveFolders()
            if optimizeExisting { optimizeOnStart.insert(folder.id) }
            if !paused { start(folder) }
        }
    }

    func update(_ folder: WatchedFolder) {
        guard folders.contains(where: { $0.id == folder.id }) else { return }
        stop(folder.id)
        folders = folders.map { $0.id == folder.id ? folder : $0 }
        saveFolders()
        if folder.isEnabled && !paused { start(folder) }
    }

    func remove(_ id: UUID) {
        stop(id)
        folders = folders.filter { $0.id != id }
        saveFolders()
        unavailableIDs.remove(id)
        optimizeOnStart.remove(id)
    }

    func setPaused(_ value: Bool) {
        paused = value
        defaults.set(value, forKey: "watchingPaused")
        if !value {
            for folder in folders where folder.isEnabled { start(folder) }
            if worker == nil && !pending.isEmpty { worker = Task { await drain() } }
        }
    }

    func relink(_ id: UUID, to url: URL) throws {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        guard url.isFileURL,
              try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw WatchError.unavailableFile
        }
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        var updated = folder
        updated.displayName = url.lastPathComponent
        updated.bookmarkData = data
        update(updated)
    }

    func displayPath(for id: UUID) -> String {
        guard let folder = folders.first(where: { $0.id == id }),
              let value = try? resolve(folder).url.path else { return folderName(id) }
        return (value as NSString).abbreviatingWithTildeInPath
    }

    func existingCount(in url: URL, recursive: Bool = false) async -> Int {
        await Task.detached(priority: .utility) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return Self.scan(url, recursive: recursive, allowed: Set(WatchFileType.allCases)).count
        }.value
    }

    func existingCount(for id: UUID) async -> Int {
        guard let folder = folders.first(where: { $0.id == id }),
              let watch = running[id] else { return 0 }
        return await Task.detached(priority: .utility) {
            Self.scan(watch.url, recursive: folder.watchSubdirectories,
                      allowed: folder.supportedTypes).count
        }.value
    }

    func optimizeExisting(_ id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        guard let watch = running[id] else {
            optimizeOnStart.insert(id)
            return
        }
        Task {
            let urls = await Task.detached(priority: .utility) {
                Self.scan(watch.url, recursive: folder.watchSubdirectories, allowed: folder.supportedTypes)
            }.value
            guard running[id] === watch else { return }
            for url in urls { enqueue(url, folderID: id) }
        }
    }

    private func folderName(_ id: UUID) -> String {
        folders.first(where: { $0.id == id })?.displayName ?? "Folder"
    }

    private func resolve(_ folder: WatchedFolder) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: folder.bookmarkData,
                          options: .withSecurityScope, relativeTo: nil,
                          bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    private func start(_ folder: WatchedFolder) {
        guard running[folder.id] == nil, starting[folder.id] == nil else { return }
        do {
            let resolved = try resolve(folder)
            guard resolved.url.startAccessingSecurityScopedResource() else { throw WatchError.permissionLost }
            do {
                if resolved.stale {
                    var refreshed = folder
                    refreshed.bookmarkData = try resolved.url.bookmarkData(
                        options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    folders = folders.map { $0.id == folder.id ? refreshed : $0 }
                    saveFolders()
                }
                let sinceID = FSEventsGetCurrentEventId()
                var started = timespec()
                clock_gettime(CLOCK_REALTIME, &started)
                let startup = Task { [weak self] in
                    let baseline = await Task.detached(priority: .utility) {
                        Self.scan(resolved.url, recursive: folder.watchSubdirectories,
                                  allowed: folder.supportedTypes)
                    }.value
                    guard let self, self.starting[folder.id] != nil else { return }
                    self.starting.removeValue(forKey: folder.id)
                    do {
                        let token = UUID()
                        let replayThroughID = FSEventsGetCurrentEventId()
                        let watcher = try FolderWatchService(folder: resolved.url, since: sinceID) {
                            [weak self] url, flags, eventID in
                            self?.event(folderID: folder.id, token: token, url: url,
                                        flags: flags, eventID: eventID)
                        }
                        self.running[folder.id] = RunningWatch(token: token, url: resolved.url,
                                                               watcher: watcher,
                                                               replayThroughID: replayThroughID,
                                                               startedSeconds: Int64(started.tv_sec),
                                                               startedNanoseconds: Int64(started.tv_nsec),
                                                               known: baseline)
                        self.unavailableIDs.remove(folder.id)
                        if self.optimizeOnStart.remove(folder.id) != nil {
                            for url in baseline { self.enqueue(url, folderID: folder.id) }
                        }
                        self.reconcile(folder.id)
                    } catch {
                        resolved.url.stopAccessingSecurityScopedResource()
                        self.unavailableIDs.insert(folder.id)
                    }
                }
                starting[folder.id] = (resolved.url, startup)
            } catch {
                resolved.url.stopAccessingSecurityScopedResource()
                throw error
            }
        } catch {
            unavailableIDs.insert(folder.id)
            logger.error("Could not start watched folder")
        }
    }

    private func stop(_ id: UUID) {
        if let (url, task) = starting.removeValue(forKey: id) {
            task.cancel()
            url.stopAccessingSecurityScopedResource()
        }
        if let watch = running.removeValue(forKey: id) { watch.stop() }
        pending.removeAll { $0.1 == id }
        queuedURLs = Set(pending.map(\.0))
        if activeFolderID == id { activeTask?.cancel() }
    }

    private func event(folderID: UUID, token: UUID, url: URL,
                       flags: FSEventStreamEventFlags, eventID: FSEventStreamEventId) {
        guard let watch = running[folderID], watch.token == token else { return }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
            stop(folderID)
            unavailableIDs.insert(folderID)
            return
        }
        guard let folder = folders.first(where: { $0.id == folderID }) else { return }
        let dropped = kFSEventStreamEventFlagMustScanSubDirs |
            kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
        if flags & FSEventStreamEventFlags(dropped) != 0 {
            reconcile(folderID)
            return
        }
        guard Self.isContained(url, in: watch.url, recursive: folder.watchSubdirectories) else { return }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 {
            if folder.watchSubdirectories { reconcile(folderID) }
            return
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            watch.known.remove(url)
            retryOnChange.removeValue(forKey: url)
            return
        }
        guard WatchFilePolicy.isEligibleFile(url, allowed: folder.supportedTypes) else { return }
        if watch.known.contains(url) {
            let createdDuringScan = eventID <= watch.replayThroughID &&
                flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated |
                    kFSEventStreamEventFlagItemRenamed) != 0 &&
                ((try? FileFingerprint.read(url))?.changed(
                    afterSeconds: watch.startedSeconds,
                    nanoseconds: watch.startedNanoseconds) == true)
            if !createdDuringScan {
                guard let failed = retryOnChange[url],
                      let current = try? FileFingerprint.read(url), !current.matches(failed) else { return }
                retryOnChange.removeValue(forKey: url)
            }
        }
        watch.known.insert(url)
        enqueue(url, folderID: folderID)
    }

    private func reconcile(_ id: UUID) {
        guard let watch = running[id],
              let folder = folders.first(where: { $0.id == id }) else { return }
        watch.debounce?.cancel()
        watch.debounce = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let current = await Task.detached(priority: .utility) {
                Self.scan(watch.url, recursive: folder.watchSubdirectories, allowed: folder.supportedTypes)
            }.value
            guard !Task.isCancelled, running[id] === watch else { return }
            guard FileManager.default.fileExists(atPath: watch.url.path) else {
                stop(id)
                unavailableIDs.insert(id)
                return
            }
            let added = current.subtracting(watch.known)
            watch.known = current
            for url in added { enqueue(url, folderID: id) }
        }
    }

    nonisolated private static func scan(_ root: URL, recursive: Bool,
                                         allowed: Set<WatchFileType>) -> Set<URL> {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey]
        let urls: [URL]
        if recursive {
            let sequence = manager.enumerator(at: root, includingPropertiesForKeys: keys,
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants])
            urls = sequence?.compactMap { $0 as? URL } ?? []
        } else {
            urls = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles])) ?? []
        }
        return Set(urls.filter { WatchFilePolicy.isEligibleFile($0, allowed: allowed) })
    }

    nonisolated private static func isContained(_ url: URL, in root: URL, recursive: Bool) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent.path == rootPath || (recursive && parent.path.hasPrefix(rootPath + "/")) else {
            return false
        }
        var ancestor = parent
        while ancestor.path != rootPath {
            guard let values = try? ancestor.resourceValues(forKeys: [.isPackageKey, .isSymbolicLinkKey]),
                  values.isPackage != true, values.isSymbolicLink != true else { return false }
            ancestor.deleteLastPathComponent()
        }
        return true
    }

    private func enqueue(_ url: URL, folderID: UUID, attempt: Int = 0, delay: TimeInterval = 0) {
        if recent.count > 500 {
            recent = recent.filter { Date().timeIntervalSince($0.value.1) < 300 }
        }
        guard !paused, !queuedURLs.contains(url), activeURL != url,
              let folder = folders.first(where: { $0.id == folderID && $0.isEnabled }),
              let watch = running[folderID],
              Self.isContained(url, in: watch.url, recursive: folder.watchSubdirectories),
              WatchFilePolicy.isEligibleFile(url, allowed: folder.supportedTypes) else { return }
        if let previous = recent[url], Date().timeIntervalSince(previous.1) < 300,
           let current = try? FileFingerprint.read(url), current.matches(previous.0) { return }
        pending.append((url, folderID, attempt, Date().addingTimeInterval(delay)))
        queuedURLs.insert(url)
        if worker == nil { worker = Task { await drain() } }
    }

    private func drain() async {
        while let index = pending.firstIndex(where: { !paused || $0.1 == clipboardOwnerID }) {
            let next = pending[index]
            if next.3 > Date() {
                // Backoff remains interruptible by newly admitted clipboard work.
                if let ready = pending.firstIndex(where: { $0.1 == clipboardOwnerID }) {
                    let item = pending.remove(at: ready)
                    await runClipboard(item.0)
                } else {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                continue
            }
            let (url, id, attempt, _) = pending.remove(at: index)
            if id == clipboardOwnerID { await runClipboard(url); continue }
            queuedURLs.remove(url)
            guard let folder = folders.first(where: { $0.id == id && $0.isEnabled }),
                  !paused, running[id] != nil else { continue }
            activeURL = url
            activeFolderID = id
            currentFileName = url.lastPathComponent
            activePhase = .checkingFile
            let job = Task.detached(priority: .utility) { [self] in
                await AutoOptimizationService().process(url, in: folder) { phase in
                    await updatePhase(phase, for: url)
                }
            }
            activeTask = job
            let result = await job.value
            if let current = try? FileFingerprint.read(url) { recent[url] = (current, Date()) }
            if let output = result.outputURL {
                if let current = try? FileFingerprint.read(output) { recent[output] = (current, Date()) }
                for (watchID, watch) in running {
                    guard let setting = folders.first(where: { $0.id == watchID }),
                          WatchFilePolicy.isEligibleFile(output, allowed: setting.supportedTypes) else { continue }
                    let parent = output.deletingLastPathComponent().standardizedFileURL.path
                    let root = watch.url.standardizedFileURL.path
                    if parent == root || (setting.watchSubdirectories && parent.hasPrefix(root + "/")) {
                        watch.known.insert(output)
                    }
                }
                pending.removeAll { $0.0 == output }
                queuedURLs.remove(output)
            }
            if result.retryable && attempt < 3, running[id] != nil,
               folders.contains(where: { $0.id == id && $0.isEnabled }) {
                // Keep retries in the same queue so waiting counts include the backoff.
                pending.append((url, id, attempt + 1, Date().addingTimeInterval(5)))
                queuedURLs.insert(url)
            }
            if !result.retryable || attempt >= 3 {
                if result.retryable, let current = try? FileFingerprint.read(url) {
                    retryOnChange[url] = current
                }
                record(result.activity)
            }
            activeTask = nil
            activeURL = nil
            activeFolderID = nil
            currentFileName = nil
        }
        worker = nil
    }

    private func updatePhase(_ phase: OptimizationJobPhase, for url: URL) {
        guard activeURL == url else { return }
        activePhase = phase
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) { defaults.set(data, forKey: "watchedFolders") }
    }
}
