import AppKit
import ServiceManagement
import SwiftUI

struct WatchedFoldersSettingsView: View {
    @Environment(WatchedFoldersController.self) private var watcher
    @Environment(\.openWindow) private var openWindow
    @State private var issue: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Watched Folders").font(.title3.weight(.semibold))
                Spacer()
                Button("Add Folder", systemImage: "plus") { chooseFolders() }
            }
            Text("Optimize new images and PDFs while OrbitConvert is running. Files stay on your Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Pause Watching", isOn: Binding(
                get: { watcher.paused }, set: { watcher.setPaused($0) }
            ))
            .toggleStyle(.switch).controlSize(.small)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if watcher.folders.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No watched folders yet").font(.headline)
                                Text("Add a folder to get started. You can include existing files when adding it.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(watcher.folders) { folder in folderRow(folder) }
                        }
                    }
                    recentActivity
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Toggle("Launch OrbitConvert at Login", isOn: Binding(
                get: { launchAtLogin }, set: { setLaunchAtLogin($0) }
            ))
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
        }
        .padding(.top, 8)
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                Text("Recent Activity").font(.headline)
                Spacer()
                Button("View All Activity") { openWindow(id: "activity") }
                    .disabled(watcher.activity.isEmpty)
            }
            Text("Last 200 watched-folder and clipboard results, saved on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if watcher.activity.isEmpty {
                Text("Completed optimizations will appear here with original size, final size, and savings.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(watcher.activity.prefix(5)) { event in
                    WatchResultRow(event: event)
                }
            }
        }
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

}
