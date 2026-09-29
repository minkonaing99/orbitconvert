import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConversionControlsView: View {
    let file: FileItem

    @State private var jpegQuality = 0.90
    @State private var stripMetadata = false
    @State private var isConverting = false
    @State private var isChoosingFolder = false
    @State private var isShowingRadial = false
    @State private var pendingFormat: ConversionFormat?
    @State private var message: String?
    @State private var resultURL: URL?
    @State private var worker: Task<Result<ConversionResult, Error>, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Convert to")
                    .foregroundStyle(.secondary)
                ForEach(file.supportedConversions) { format in
                    Button(format.label) { convert(to: format, in: file.url.deletingLastPathComponent()) }
                        .disabled(isConverting)
                        .accessibilityLabel("Convert \(file.fileName) to \(format.label)")
                }
                Button("Radial Menu") { isShowingRadial.toggle() }
                    .disabled(isConverting || file.supportedConversions.isEmpty)
            }
            if isShowingRadial {
                RadialMenuView(file: file, actions: file.supportedConversions.map { FileAction(format: $0) }) { action in
                    isShowingRadial = false
                    convert(to: action.format, in: file.url.deletingLastPathComponent())
                } onDismiss: {
                    isShowingRadial = false
                }
            }
            HStack(spacing: 16) {
                if file.supportedConversions.contains(.jpeg) {
                    HStack {
                        Text("JPEG quality")
                        Slider(value: $jpegQuality, in: 0...1)
                            .frame(width: 120)
                        Text(jpegQuality.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                    }
                }
                Toggle("Remove metadata", isOn: $stripMetadata)
            }
            .font(.caption)
            if isConverting {
                HStack {
                    ProgressView("Converting \(file.fileName)...")
                        .controlSize(.small)
                    Button("Cancel") { worker?.cancel() }
                }
            }
            if let message {
                HStack(spacing: 8) {
                    Text(message)
                        .foregroundStyle(resultURL == nil ? .red : .secondary)
                    if let resultURL {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([resultURL])
                        }
                    }
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { selection in
            guard let format = pendingFormat else { return }
            pendingFormat = nil
            switch selection {
            case .success(let folder): convert(to: format, in: folder)
            case .failure: message = "No output folder was selected."
            }
        }
    }

    private func convert(to format: ConversionFormat, in directory: URL) {
        guard !isConverting else { return }
        isShowingRadial = false
        isConverting = true
        message = nil
        resultURL = nil
        let item = file
        let options = ConversionOptions(jpegQuality: jpegQuality, stripMetadata: stripMetadata)
        let service = ImageConversionService()
        let job = Task.detached(priority: .userInitiated) {
            Result { try service.convert(item, to: format, in: directory, options: options) }
        }
        worker = job
        Task {
            let outcome = await job.value
            worker = nil
            isConverting = false
            switch outcome {
            case .success(let result):
                resultURL = result.outputURL
                message = "Saved \(result.outputURL.lastPathComponent)"
            case .failure(let error):
                if error is CancellationError {
                    message = "Conversion cancelled."
                } else if let conversionError = error as? ConversionError,
                   [.permissionDenied, .invalidDestination].contains(conversionError),
                   directory.standardizedFileURL == item.url.deletingLastPathComponent().standardizedFileURL {
                    pendingFormat = format
                    isChoosingFolder = true
                } else {
                    message = (error as? LocalizedError)?.errorDescription ?? "Conversion failed."
                }
            }
        }
    }
}
