import AppKit
import ServiceManagement
import SwiftUI

struct WatchedFoldersSettingsView: View {
    @Environment(WatchedFoldersController.self) private var watcher
    @State private var issue: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Watched Folders").font(.title3.weight(.semibold))
                Spacer()
                Button("Add Folder", systemImage: "plus") { chooseFolders() }
            }
            Text("OrbitConvert watches new files while it is running. Files stay local. Optimized files replace originals only after validation.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Pause Watching", isOn: Binding(
                get: { watcher.paused }, set: { watcher.setPaused($0) }
            ))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(watcher.folders) { folder in folderRow(folder) }
                }
            }
            if watcher.folders.isEmpty {
                ContentUnavailableView("No Watched Folders", systemImage: "folder",
                                       description: Text("Add a folder to optimize new images and PDFs automatically."))
            }
            Divider()
            Toggle("Launch OrbitConvert at Login", isOn: Binding(
                get: { launchAtLogin }, set: { setLaunchAtLogin($0) }
            ))
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
            if !watcher.activity.isEmpty {
                Text("Recent Activity").font(.headline)
                ForEach(watcher.activity.prefix(5)) { event in
                    HStack {
                        Text(event.fileName).lineLimit(1)
                        Spacer()
                        Text(activityLabel(event)).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.top, 8)
    }

    private func folderRow(_ folder: WatchedFolder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(
                    get: { folder.isEnabled },
                    set: { value in var next = folder; next.isEnabled = value; watcher.update(next) }
                )) {
                    VStack(alignment: .leading) {
                        Text(folder.displayName).fontWeight(.medium)
                        Text(watcher.displayPath(for: folder.id))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button("Remove", systemImage: "minus") { watcher.remove(folder.id) }
                    .labelStyle(.iconOnly)
            }
            if watcher.unavailableIDs.contains(folder.id) {
                HStack {
                    Label("Folder unavailable or permission lost", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Grant Access") { relink(folder) }
                }
                .font(.caption)
            }
            HStack {
                Picker("Compression", selection: Binding(
                    get: { folder.preset },
                    set: { value in var next = folder; next.preset = value; watcher.update(next) }
                )) {
                    ForEach(CompressionPreset.allCases.filter { $0 != .custom && ($0 != .lossless ||
                        folder.supportedTypes.isDisjoint(with: [.jpeg, .heic])) }) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                Picker("Original", selection: Binding(
                    get: { folder.replacementBehavior },
                    set: { value in var next = folder; next.replacementBehavior = value; watcher.update(next) }
                )) {
                    ForEach(ReplacementBehavior.allCases) { behavior in
                        Text(behavior.label).tag(behavior)
                    }
                }
            }
            HStack {
                ForEach(WatchFileType.allCases) { type in
                    Toggle(type.label, isOn: Binding(
                        get: { folder.supportedTypes.contains(type) },
                        set: { value in
                            var next = folder
                            if value { next.supportedTypes.insert(type) } else { next.supportedTypes.remove(type) }
                            if next.preset == .lossless && !next.supportedTypes.isDisjoint(with: [.jpeg, .heic]) {
                                next.preset = .balanced
                            }
                            watcher.update(next)
                        }
                    ))
                    .disabled(!type.isAvailable)
                }
            }
            HStack {
                Toggle("Watch Subfolders", isOn: Binding(
                    get: { folder.watchSubdirectories },
                    set: { value in var next = folder; next.watchSubdirectories = value; watcher.update(next) }
                ))
                Spacer()
                Button("Optimize Existing Files") { confirmExisting(folder) }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        Task {
            for url in panel.urls {
                let count = await watcher.existingCount(in: url)
                let optimize = count > 0 && confirm(
                    "This folder contains \(count) supported files.",
                    detail: "Watch new files only, or optimize existing files too?",
                    action: "Optimize \(count) Existing Files")
                do { try watcher.add([url], optimizeExisting: optimize) }
                catch { issue = error.localizedDescription }
            }
        }
    }

    private func confirmExisting(_ folder: WatchedFolder) {
        Task {
            let count = await watcher.existingCount(for: folder.id)
            guard count > 0 else { issue = "No supported files found."; return }
            if confirm("Optimize \(count) existing files?",
                       detail: "Files will use this folder's compression and original-handling settings.",
                       action: "Optimize \(count) Files", cancel: "Cancel") {
                watcher.optimizeExisting(folder.id)
            }
        }
    }

    private func relink(_ folder: WatchedFolder) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try watcher.relink(folder.id, to: url) }
        catch { issue = error.localizedDescription }
    }

    private func confirm(_ title: String, detail: String, action: String,
                         cancel: String = "Watch New Files Only") -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: cancel)
        alert.addButton(withTitle: action)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
            issue = nil
        } catch { issue = "Launch at Login could not be changed: \(error.localizedDescription)" }
    }

    private func activityLabel(_ event: WatchActivity) -> String {
        switch event.outcome {
        case .optimized:
            let saved = event.originalBytes - event.outputBytes
            return "Saved \(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file))"
        case .skipped: return "No useful reduction"
        case .failed: return event.message
        }
    }
}
