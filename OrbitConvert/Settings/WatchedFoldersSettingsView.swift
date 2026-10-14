import AppKit
import ServiceManagement
import SwiftUI

struct WatchedFoldersSettingsView: View {
    @Environment(WatchedFoldersController.self) private var watcher
    @Environment(\.openWindow) private var openWindow
    @State private var issue: String?
    @State private var editingFolder: WatchedFolder?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmingReset = false
    @AppStorage(LoadGate.settingKey) private var pauseUnderLoad = LoadGate.enabledByDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Watched Folders").font(.title3.weight(.semibold))
                Spacer()
                Button("Add Folder", systemImage: "plus") { chooseFolders() }
            }
            Text("Rename, organize, and optimize new files automatically. Files stay on your Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Pause Watching", isOn: Binding(
                get: { watcher.paused }, set: { watcher.setPaused($0) }
            ))
            .toggleStyle(.switch).controlSize(.small)
            Toggle("Wait while the Mac is warm or in Low Power Mode", isOn: $pauseUnderLoad)
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: pauseUnderLoad) { watcher.loadGate.wake() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if watcher.folders.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No watched folders yet").font(.headline)
                                Text("Add a folder, then choose what happens to new files.")
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
        .sheet(item: $editingFolder) { folder in
            AutomationRulesView(folder: folder, canRun: watcher.canRunAutomation(folder.id), onSave: { watcher.update($0) },
                onRun: { watcher.runAutomation($0, folderID: folder.id) })
        }
    }

    private var lifetimeTotal: some View {
        HStack {
            Text(watcher.lifetimeSavings.summary).font(.callout)
            Spacer()
            if confirmingReset {
                Button("Cancel") { confirmingReset = false }
                Button("Reset Total", role: .destructive) {
                    watcher.resetLifetimeSavings()
                    confirmingReset = false
                }
            } else {
                Button("Reset...") { confirmingReset = true }
            }
        }.controlSize(.small)
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
            if watcher.lifetimeSavings.bytes > 0 { lifetimeTotal }
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
                Text("\(folder.effectiveRules.filter { $0.isEnabled }.count) active rules")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Manage Rules...") { editingFolder = folder }
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
        do { try watcher.add(panel.urls, optimizeExisting: false, automation: true) }
        catch { issue = error.localizedDescription }
    }

    private func relink(_ folder: WatchedFolder) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try watcher.relink(folder.id, to: url) }
        catch { issue = error.localizedDescription }
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
