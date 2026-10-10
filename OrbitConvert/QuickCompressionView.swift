import SwiftUI

struct QuickCompressionView: View {
    @Bindable var controller: QuickCompressionController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Compress \(controller.sources.count == 1 ? "Image" : "\(controller.sources.count) Images")")
                    .font(.title2.bold())
                Text("\(controller.settings.preset.label) compression. Your images stay on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if controller.results.isEmpty {
                options
            } else {
                summary
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if controller.results.isEmpty {
                        ForEach(controller.sources, id: \.self) { url in
                            Label(url.lastPathComponent, systemImage: "photo")
                                .lineLimit(1).truncationMode(.middle).help(url.path)
                        }
                    } else {
                        ForEach(controller.results) { result in resultRow(result) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            if controller.isRunning {
                ProgressView("Compressing \(controller.completed) of \(controller.sources.count)",
                    value: Double(controller.completed), total: Double(max(1, controller.sources.count)))
            } else if !controller.status.isEmpty {
                Text(controller.status).font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                if controller.isRunning {
                    Button("Stop", action: controller.cancel)
                } else {
                    Button(controller.results.isEmpty ? "Cancel" : "Done", action: controller.close)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                if controller.results.isEmpty {
                    Button(controller.mode == .replaceOriginal ? "Compress & Replace" : "Compress", action: controller.compress)
                        .keyboardShortcut(.defaultAction).disabled(controller.isRunning)
                } else if controller.results.contains(where: { $0.compression != nil }) {
                    Button("Show in Finder", action: controller.reveal).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24).frame(width: 520, height: 480)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Save compressed images", selection: $controller.mode) {
                ForEach(QuickCompressionMode.allCases) { mode in Text(mode.label).tag(mode) }
            }
            Text(controller.mode.detail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Files that cannot be made smaller are kept unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(controller.isRunning)
    }

    private var summary: some View {
        let saved = controller.results.compactMap(\.compression)
        let original = saved.reduce(Int64(0)) { $0 + $1.originalBytes }
        let output = saved.reduce(Int64(0)) { $0 + $1.outputBytes }
        let percentage = CompressionResult.savingsPercentage(original: original, output: output)
        return VStack(alignment: .leading, spacing: 5) {
            Text("Saved \(bytes(original - output)) (\(percentage.formatted(.number.precision(.fractionLength(1))))%)")
                .font(.headline)
            Text("\(saved.count) of \(controller.sources.count) images compressed")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func resultRow(_ result: QuickCompressionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(result.source.lastPathComponent,
                systemImage: result.failed ? "exclamationmark.circle" : result.compression == nil ? "minus.circle" : "checkmark.circle")
                .lineLimit(1).truncationMode(.middle)
            if let saved = result.compression {
                Text("\(bytes(saved.originalBytes)) to \(bytes(saved.outputBytes)) - \(saved.savingsPercentage.formatted(.number.precision(.fractionLength(1))))% smaller")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(result.message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
