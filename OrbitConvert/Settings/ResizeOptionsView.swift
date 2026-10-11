import SwiftUI

struct ResizeOptionsView: View {
    let files: [FileItem]
    @Binding var options: ResizeOptions
    @Binding var compressionPreset: CompressionPreset
    let onCancel: () -> Void
    let onRun: () -> Void
    @State private var sourceDimensions: [URL: ResizeDimensions] = [:]
    @State private var dimensionsLoaded = false

    private var previews: [(FileItem, ResizeDimensions)] {
        files.compactMap { file in
            guard let source = sourceDimensions[file.url],
                  let dimensions = try? options.dimensions(width: source.width, height: source.height) else {
                return nil
            }
            return (file, dimensions)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resize + Optimize").font(.title2.bold())
            Picker("Size", selection: $options.preset) {
                ForEach(ResizePreset.allCases) { preset in Text(preset.label).tag(preset) }
            }
            if options.preset == .custom {
                HStack {
                    TextField("Maximum width", value: $options.width, format: .number)
                        .accessibilityLabel("Maximum width in pixels")
                    Text("x")
                    TextField("Maximum height", value: $options.height, format: .number)
                        .accessibilityLabel("Maximum height in pixels")
                    Text("px")
                }
                Text("Fits within these bounds while preserving aspect ratio.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Compression", selection: $compressionPreset) {
                Text("Balanced").tag(CompressionPreset.balanced)
                Text("Maximum").tag(CompressionPreset.aggressive)
            }
            if previews.count == files.count {
                ForEach(previews.prefix(3), id: \.0.id) { file, dimensions in
                    HStack {
                        Text(file.fileName).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(dimensions.width) x \(dimensions.height) px").monospacedDigit()
                    }.font(.caption)
                }
                if files.count > 3 { Text("And \(files.count - 3) more files").font(.caption) }
            } else if !dimensionsLoaded {
                ProgressView("Checking image dimensions...").controlSize(.small)
            } else {
                Text("Check the image and enter positive dimensions within the supported limits.")
                    .foregroundStyle(.red).font(.caption)
            }
            Text("Never enlarges. Keeps the original format and saves a separate file only when smaller. PNG transparency is preserved.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(files.count > 1 ? "Resize Selected" : "Resize", action: onRun)
                    .keyboardShortcut(.defaultAction)
                    .disabled(previews.count != files.count || files.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .task(id: files.map(\.url)) {
            dimensionsLoaded = false
            sourceDimensions = [:]
            let selection = files
            let dimensions = await Task.detached(priority: .userInitiated) {
                var result: [URL: ResizeDimensions] = [:]
                for file in selection {
                    if let size = try? ImageResizeService().displayDimensions(for: file) {
                        result[file.url] = size
                    }
                }
                return result
            }.value
            guard !Task.isCancelled else { return }
            sourceDimensions = dimensions
            dimensionsLoaded = true
        }
    }
}
