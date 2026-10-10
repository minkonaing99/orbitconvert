import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class QuickCompressionController: NSObject, NSWindowDelegate {
    let sources: [URL]
    let settings: QuickCompressionSettings
    var mode: QuickCompressionMode
    private(set) var results: [QuickCompressionResult] = []
    private(set) var isRunning = false
    private(set) var completed = 0
    private(set) var status = ""
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var sourceGrants: [URL] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var closed = false
    @ObservationIgnored var onClose: (() -> Void)?

    init(sources: [URL], defaults: UserDefaults = .standard) {
        self.sources = sources
        self.defaults = defaults
        settings = QuickCompressionSettings(defaults: defaults)
        mode = QuickCompressionMode(savedValue: defaults.string(forKey: "quickCompressionMode"))
        super.init()
        sourceGrants = sources.filter { $0.startAccessingSecurityScopedResource() }
    }

    func show() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Compress with OrbitConvert"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: QuickCompressionView(controller: self))
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func compress() {
        guard !isRunning, results.isEmpty, let window else { return }
        let selectedMode = mode
        isRunning = true
        status = ""
        task = Task { [self] in
            defer {
                isRunning = false
                task = nil
                if closed { releaseSourceGrants() }
            }
            guard let folders = await selectFolders(for: selectedMode, window: window),
                  !Task.isCancelled else {
                if status.isEmpty { status = "Canceled. No files changed." }
                return
            }
            let grants = folders.filter { $0.startAccessingSecurityScopedResource() }
            defer { grants.forEach { $0.stopAccessingSecurityScopedResource() } }
            defaults.set(selectedMode.rawValue, forKey: "quickCompressionMode")
            let sources = self.sources
            let settings = self.settings
            let destination = selectedMode == .chooseFolder ? folders.first : nil
            let worker = Task.detached(priority: .userInitiated) { [weak self] in
                QuickCompressionService().run(sources, mode: selectedMode, destination: destination,
                    settings: settings) { [weak self] count in
                    Task { @MainActor [weak self] in self?.completed = count }
                }
            }
            results = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            status = Task.isCancelled ? "Stopped. Completed files are listed below." : "Finished"
        }
    }

    private func selectFolders(for mode: QuickCompressionMode, window: NSWindow) async -> [URL]? {
        let parents = sources.reduce(into: [URL]()) { folders, source in
            let parent = source.deletingLastPathComponent()
            if !folders.contains(parent) { folders.append(parent) }
        }
        let requested: [URL?] = mode == .chooseFolder ? [nil] : parents.map { Optional($0) }
        var selected: [URL] = []
        for parent in requested {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = mode == .chooseFolder
            panel.directoryURL = parent
            panel.prompt = parent == nil ? "Choose Folder" : "Allow Access"
            panel.message = parent.map { "Allow OrbitConvert to save in \($0.lastPathComponent). Select this folder to continue." }
                ?? "Choose where to save the compressed copies."
            guard await panel.beginSheetModal(for: window) == .OK, let folder = panel.url,
                  !Task.isCancelled else { return nil }
            if let parent, folder.resolvingSymlinksInPath().standardizedFileURL != parent.resolvingSymlinksInPath().standardizedFileURL {
                status = "Select the original folder, or use Choose Output Folder."
                return nil
            }
            selected.append(folder)
        }
        return selected
    }

    func cancel() { task?.cancel() }
    func close() { window?.close() }
    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(results.compactMap { $0.compression?.outputURL })
    }

    func windowWillClose(_ notification: Notification) {
        closed = true
        cancel()
        if !isRunning { releaseSourceGrants() }
        window = nil
        onClose?()
        onClose = nil
    }

    private func releaseSourceGrants() {
        sourceGrants.forEach { $0.stopAccessingSecurityScopedResource() }
        sourceGrants = []
    }
}
