import SwiftUI

struct TargetSizeOptionsView: View {
    let count: Int
    let onCancel: () -> Void
    let onRun: (Int64) -> Void
    @State private var amount = "2"
    @State private var megabytes = true

    private var targetBytes: Int64? { try? TargetSizeOptions.bytes(amount: amount, megabytes: megabytes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Compress to Size").font(.title2.bold())
            HStack {
                TextField("Maximum size per file", text: $amount)
                    .accessibilityLabel("Maximum size per file")
                Picker("Unit", selection: $megabytes) {
                    Text("KB").tag(false)
                    Text("MB").tag(true)
                }.frame(width: 110)
            }
            Text("1 MB = 1,000,000 bytes. Applies to each selected JPEG.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Lowers JPEG quality first, then resizes if needed. Resizing preserves aspect ratio and keeps the short edge at least 1080 px (1920 x 1080 for 16:9). Smaller originals keep their dimensions.")
                .font(.callout)
            Text("Saves a separate file. Images already within the limit are left unchanged.")
                .font(.caption).foregroundStyle(.secondary)
            if targetBytes == nil {
                Text("Enter a target between 1 byte and 1,000 MB.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(count > 1 ? "Compress Selected" : "Compress") {
                    if let targetBytes { onRun(targetBytes) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(targetBytes == nil || count == 0)
            }
        }.padding(24).frame(width: 420)
    }
}
