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
                appBehavior
                fileQuality
                privacy
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            ClipboardSettingsView()
                .tabItem { Label("Clipboard", systemImage: "clipboard") }
            WatchedFoldersSettingsView()
                .tabItem { Label("Watched Folders", systemImage: "folder.badge.gearshape") }
        }
        .padding(20)
        .frame(width: 590, height: 480)
    }

    private var appBehavior: some View {
        Section("App Behavior") {
            Toggle(isOn: $hideDockIcon) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hide from the Dock")
                    Text("Open OrbitConvert from the menu bar at the top of your screen. Choose Quit there to close it.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: hideDockIcon) { _, hidden in
                OrbitConvertAppDelegate.updateDockVisibility(hidden: hidden)
            }
        }
    }

    private var fileQuality: some View {
        Section("File Size & Quality") {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Compression level", selection: $preset) {
                    ForEach(CompressionPreset.allCases.filter { $0 != .custom }) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                Text("Balanced is a good starting point. Maximum aims for smaller files, but may reduce image detail. PNG images keep their quality.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Lossless keeps image quality and is unavailable for JPEG images.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("JPEG output quality")
                    Spacer()
                    Text(jpegExportQuality.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $jpegExportQuality, in: 0...1)
                    .labelsHidden()
                    .accessibilityLabel("JPEG output quality")
                    .accessibilityValue(jpegExportQuality.formatted(.percent.precision(.fractionLength(0))))
                Text("Higher quality keeps more detail and creates larger files. Applies when converting to JPEG, including PDF pages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker("PDF image size", selection: $pdfImageDPI) {
                    Text("Small (72 DPI)").tag(72)
                    Text("Medium (100 DPI)").tag(100)
                    Text("Standard (150 DPI)").tag(150)
                    Text("Large (200 DPI)").tag(200)
                    Text("Extra large (300 DPI)").tag(300)
                }
                Text("For saving PDF pages as images. Larger images show more detail and use more storage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var privacy: some View {
        Section {
            Toggle(isOn: $removeMetadata) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remove hidden file details")
                    Text("Remove details such as photo location, camera information, and author names from supported exports.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.toggleStyle(.switch)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Main-window conversions keep your original. Finder Quick Actions and watched folders follow their own save choices.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
