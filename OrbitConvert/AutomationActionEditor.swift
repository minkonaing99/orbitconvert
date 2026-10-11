import AppKit
import SwiftUI

struct AutomationActionEditor: View {
    @Binding var action: AutomationAction
    @State private var issue: String?
    @State private var previewDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: value(\.kind)) {
                ForEach(AutomationActionKind.allCases) { Text($0.rawValue).tag($0) }
            }.frame(maxWidth: 240)
            switch action.kind {
            case .rename: renameOptions
            case .move, .copy: destinationOptions
            case .compress: compressionOptions
            case .convert: conversionOptions
            case .resize: resizeOptions
            case .removeMetadata:
                Text("Creates an image or PDF copy without supported hidden details. Later actions use the copy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var renameOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Rename pattern", text: value(\.template))
            HStack(spacing: 4) {
                ForEach(["{name}", "{ext}", "yyyy-MM-dd", "HH-mm-ss", "{i}", "{i:03}"], id: \.self) { token in
                    Button(token) {
                        var next = action; next.template += token; action = next
                    }.controlSize(.small)
                }
            }
            Text(renamePreview).font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled).lineLimit(2)
            Text("Uses creation date (modified date if missing). MM = month; mm = minute. Quote literal text: 'Photo'. Extension stays; {i} finds the next unused number.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var renamePreview: String {
        do {
            let template = try AutomationRenameTemplate(action.template)
            return "Preview: " + (try template.render(originalName: "Photo", fileExtension: "png",
                creationDate: previewDate, modificationDate: nil, index: 1))
        } catch { return error.localizedDescription }
    }

    private var destinationOptions: some View {
        HStack {
            Label(action.destinationName, systemImage: "folder")
                .lineLimit(2).truncationMode(.middle).help(action.destinationName)
            Spacer()
            Button("Choose...") { chooseDestination() }
        }
    }

    private var compressionOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Compression", selection: value(\.preset)) {
                    ForEach(CompressionPreset.allCases.filter { $0 != .custom }) {
                        Text($0.label).tag($0)
                    }
                }
                Picker("Original", selection: value(\.replacement)) {
                    ForEach(ReplacementBehavior.allCases.filter {
                        $0 != .moveOriginalToTrash || action.replacement == .moveOriginalToTrash
                    }) { Text($0.label).tag($0) }
                }
            }
            Text("Supports JPEG, PNG, HEIC and PDF. Lossless is unavailable for JPEG and HEIC.")
                .font(.caption).foregroundStyle(.secondary)
            Text(action.replacement == .keepBoth
                 ? "Keep Both protects the original; later actions use the compressed copy."
                 : "Replaces the original only with a validated smaller file. This cannot be undone in OrbitConvert.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var conversionOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Output format", selection: value(\.format)) {
                ForEach(["jpeg", "png", "heic", "tiff", "pdf"], id: \.self) { Text($0.uppercased()).tag($0) }
            }
            if action.format == "jpeg" {
                HStack {
                    Slider(value: value(\.quality), in: 0.1...1).accessibilityLabel("JPEG quality")
                    Text(action.quality, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
            }
            Text("Converts images only. Creates a copy; later actions use the converted file.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var resizeOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Maximum width", value: value(\.width), format: .number)
                Text("x")
                TextField("Maximum height", value: value(\.height), format: .number)
                Text("pixels").foregroundStyle(.secondary)
            }
            Text("Fits images within these dimensions, preserving proportions. Creates a copy; later actions use it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func value<T>(_ keyPath: WritableKeyPath<AutomationAction, T>) -> Binding<T> {
        Binding(get: { action[keyPath: keyPath] }, set: { value in
            var next = action; next[keyPath: keyPath] = value; action = next
        })
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil, relativeTo: nil)
            var next = action
            next.destinationBookmark = bookmark
            next.destinationName = url.path
            action = next
            issue = nil
        } catch { issue = "Could not save folder access: " + error.localizedDescription }
    }
}
