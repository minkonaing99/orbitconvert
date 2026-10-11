import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @Environment(WatchedFoldersController.self) private var watcher
    var body: some View {
        @Bindable var clipboard = watcher.clipboard
        Form {
            Toggle("Automatically optimize copied images", isOn: $clipboard.enabled)
            Toggle("Optimize images", isOn: $clipboard.optimizeImages)
            Toggle("Optimize copied image files", isOn: $clipboard.optimizeFiles)
            Text("Copied files paste as temporary optimized files. Source files are never changed. Temporary files remain available while referenced by the clipboard.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Compression", selection: $clipboard.preset) {
                ForEach(CompressionPreset.allCases.filter { $0 != .custom }) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            Text("PNG and TIFF-to-PNG preserve pixels and transparency. Lossless JPEG/HEIC optimization is unavailable.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show result after optimization", isOn: $clipboard.showResults)
            Toggle("Collect clipboard results", isOn: $clipboard.collectResults)
            Text("Collection stays in memory, up to 20 images or 128 MB. Copy All creates multiple clipboard items; destination app support varies.")
                .font(.caption).foregroundStyle(.secondary)
            Section("Ignored Apps") {
                ForEach(clipboard.ignoredApps, id: \.self) { identifier in
                    HStack {
                        Text(identifier).lineLimit(1)
                        Spacer()
                        Button("Remove") { clipboard.ignoredApps = clipboard.ignoredApps.filter { $0 != identifier } }
                    }
                }
                Button("Add Application...") { chooseApplication() }
            }
            Text("Local processing only. macOS may ask permission to read image content. Text and confidential clipboard items are ignored.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            let identifiers = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            watcher.clipboard.ignoredApps = Array(Set(watcher.clipboard.ignoredApps + identifiers)).sorted()
        }
    }
}
