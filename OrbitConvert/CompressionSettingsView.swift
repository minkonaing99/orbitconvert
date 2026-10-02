import SwiftUI

struct CompressionSettingsView: View {
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("defaultCompressionPreset") private var preset = CompressionPreset.balanced.rawValue
    @AppStorage("jpegExportQuality") private var jpegExportQuality = 0.90
    @AppStorage("pdfImageDPI") private var pdfImageDPI = 150
    @AppStorage("removeMetadata") private var removeMetadata = false

    var body: some View {
        TabView {
            Form {
            Toggle("Hide Dock icon", isOn: $hideDockIcon)
                .onChange(of: hideDockIcon) { _, hidden in
                    OrbitConvertAppDelegate.updateDockVisibility(hidden: hidden)
                }
            Text("Keep OrbitConvert in the menu bar when windows are closed. Choose Quit from the menu bar to exit.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Default compression", selection: $preset) {
                ForEach(CompressionPreset.allCases.filter { $0 != .custom }) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            Text("Lossless JPEG optimization is unavailable. JPEG Balanced and Maximum use fixed quality; PNG optimization is lossless.")
                .foregroundStyle(.secondary)
            Text("PNG uses Oxipng. Maximum spends more time compressing while preserving pixels and transparency.")
                .foregroundStyle(.secondary)
            HStack {
                Slider(value: $jpegExportQuality, in: 0...1) {
                    Text("JPEG export quality")
                }
                Text(jpegExportQuality.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
            }
            Picker("PDF to image resolution", selection: $pdfImageDPI) {
                ForEach([72, 100, 150, 200, 300], id: \.self) { dpi in
                    Text("\(dpi) DPI").tag(dpi)
                }
            }
            Toggle("Remove metadata by default", isOn: $removeMetadata)
            Text("Manual conversions and compression keep the original. Watched folders use their own replacement setting.")
                .foregroundStyle(.secondary)
            }
            .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            ClipboardSettingsView()
                .tabItem { Label("Clipboard", systemImage: "clipboard") }
            WatchedFoldersSettingsView()
                .tabItem { Label("Watched Folders", systemImage: "folder.badge.gearshape") }
        }
        .padding(20)
        .frame(width: 590, height: 480)
    }
}
