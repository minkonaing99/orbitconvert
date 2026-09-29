import SwiftUI

struct CompressionSettingsView: View {
    @AppStorage("defaultCompressionPreset") private var preset = CompressionPreset.balanced.rawValue
    @AppStorage("jpegExportQuality") private var jpegExportQuality = 0.90
    @AppStorage("pdfImageDPI") private var pdfImageDPI = 150
    @AppStorage("removeMetadata") private var removeMetadata = false

    var body: some View {
        Form {
            Picker("Default compression", selection: $preset) {
                ForEach(CompressionPreset.allCases.filter { $0 != .custom }) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            Text("Lossless JPEG optimization is unavailable. JPEG Balanced and Maximum use fixed quality; PNG optimization is lossless.")
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
            Text("Converted and optimized files are saved beside the source. The original is always kept.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
    }
}
