import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConversionControlsView: View {
    let file: FileItem
    let selection: [FileItem]
    let autoOpenPanel: Bool
    let onFloatingOpened: () -> Void

    @AppStorage("defaultCompressionPreset") private var defaultPreset = CompressionPreset.balanced.rawValue
    @AppStorage("jpegExportQuality") private var jpegQuality = 0.90
    @AppStorage("removeMetadata") private var stripMetadata = false
    @AppStorage("pdfImageDPI") private var pdfDPI = 150
    @State private var pdfLayout = PDFPageLayout.fit
    @State private var pageSelection = "all"
    @State private var isConverting = false
    @State private var isChoosingFolder = false
    @State private var floatingController: FloatingActionPanelController?
    @State private var pendingAction: FileAction?
    @State private var message: String?
    @State private var isError = false
    @State private var resultURLs: [URL] = []
    @State private var compression: CompressionResult?
    @State private var progressText: String?
    @State private var lastAction: FileAction?
    @State private var worker: Task<Result<FileActionReport, Error>, Never>?

    private var actions: [FileAction] { FileAction.available(for: file, selection: selection) }
    private var preset: CompressionPreset {
        get { CompressionPreset(rawValue: defaultPreset) ?? .balanced }
        nonmutating set { defaultPreset = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FileActionPanelView(file: file, actions: actions, isEnabled: !isConverting,
                                returnSelectsFirstAction: false) { action in
                process(action, in: file.url.deletingLastPathComponent())
            } onDismiss: {} onFocusChanged: { _ in }
            Button("Open Floating Panel") { showFloatingPanel() }
                .disabled(isConverting || actions.isEmpty)
                .accessibilityHint("Opens file actions near the pointer")
            if !actions.isEmpty {
                options
            }
            if isConverting {
                HStack {
                    ProgressView(progressText ?? "Processing \(file.fileName)...")
                        .controlSize(.small)
                    Button("Cancel") { worker?.cancel() }
                }
            }
            if let message {
                VStack(alignment: .leading, spacing: 6) {
                    Label(isError ? "Action Failed" : lastAction?.kind == .compress ? "Optimization Finished" : lastAction?.category == .tool ? "Action Complete" : "Conversion Complete",
                          systemImage: isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isError ? .red : .primary)
                    Text(message).font(.caption)
                    if let compression {
                        resultRow("Original", value: size(compression.originalBytes))
                        resultRow("Optimized", value: size(compression.outputBytes))
                        resultRow("Saved", value: size(compression.savingsBytes))
                        resultRow("Reduction", value: "\(compression.savingsPercentage.formatted(.number.precision(.fractionLength(0))))%")
                    }
                    if !resultURLs.isEmpty {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(resultURLs)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: 420, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Output: same folder as source unless another folder is selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { selection in
            guard let action = pendingAction else { return }
            pendingAction = nil
            switch selection {
            case .success(let folder): process(action, in: folder)
            case .failure: message = "No output folder was selected."
            }
        }
        .onDisappear { floatingController?.dismiss() }
        .task(id: autoOpenPanel) {
            guard autoOpenPanel else { return }
            showFloatingPanel()
            onFloatingOpened()
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                if actions.contains(where: { $0.kind == .pdfJPEG || $0.kind == .convert(.jpeg) }) {
                    HStack {
                        Text("JPEG quality")
                        Slider(value: $jpegQuality, in: 0...1).frame(width: 120)
                        Text(jpegQuality.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                    }
                }
                Toggle("Remove metadata", isOn: $stripMetadata)
            }
            if actions.contains(where: { $0.kind == .compress }), file.contentTypeIdentifier == UTType.png.identifier {
                Text("PNG optimization preserves exact pixels and transparency.")
                    .foregroundStyle(.secondary)
            } else if actions.contains(where: { $0.kind == .compress }) {
                Picker("Compression", selection: Binding(get: { preset }, set: { preset = $0 })) {
                    ForEach(CompressionPreset.allCases.filter { $0 != .custom }) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 330)
                if preset == .lossless && ConversionFormat.sourceFormat(for: file.contentTypeIdentifier) == .jpeg {
                    Text("Lossless JPEG optimization is unavailable. Choose Balanced or Maximum.")
                        .foregroundStyle(.secondary)
                }
            }
            if file.isPDF {
                HStack {
                    Picker("Resolution", selection: $pdfDPI) {
                        ForEach([72, 100, 150, 200, 300], id: \.self) { dpi in Text("\(dpi) DPI").tag(dpi) }
                    }
                    .frame(width: 180)
                    TextField("Pages: all, 4, or 4-7", text: $pageSelection)
                        .frame(width: 170)
                        .accessibilityLabel("Pages to extract")
                }
            } else {
                Picker("PDF page size", selection: $pdfLayout) {
                    ForEach(PDFPageLayout.allCases) { layout in Text(layout.label).tag(layout) }
                }
                .frame(width: 220)
            }
        }
        .font(.caption)
    }

    private func showFloatingPanel() {
        floatingController?.dismiss()
        let controller = FloatingActionPanelController(
            file: file, actions: actions,
            onSelect: { action in process(action, in: file.url.deletingLastPathComponent()) },
            onClose: { floatingController = nil }
        )
        floatingController = controller
        if !controller.show() { message = "No screen can display the floating panel." }
    }

    private func process(_ action: FileAction, in directory: URL) {
        guard !isConverting else { return }
        floatingController?.dismiss()
        isConverting = true
        isError = false
        lastAction = action
        message = nil
        compression = nil
        resultURLs = []
        progressText = "Preparing..."
        let item = file
        let files = selection
        let settings = FileActionSettings(jpegQuality: jpegQuality, stripMetadata: stripMetadata,
                                          compressionPreset: file.contentTypeIdentifier == UTType.png.identifier ? .lossless : preset, pdfDPI: pdfDPI,
                                          pdfLayout: pdfLayout, pageSelection: pageSelection)
        let (updates, continuation) = AsyncStream<String>.makeStream()
        Task { for await update in updates { progressText = update } }
        let job = Task.detached(priority: .userInitiated) {
            defer { continuation.finish() }
            return Result {
                try FileActionService().execute(action, for: item, selection: files,
                                                in: directory, settings: settings,
                                                progress: { continuation.yield($0) })
            }
        }
        worker = job
        Task {
            let outcome = await job.value
            worker = nil
            isConverting = false
            progressText = nil
            switch outcome {
            case .success(let report):
                resultURLs = report.outputURLs
                compression = report.compression
                message = report.message
            case .failure(let error):
                if error is CancellationError {
                    message = "Operation cancelled."
                } else if let conversionError = error as? ConversionError,
                          [.permissionDenied, .invalidDestination].contains(conversionError),
                          directory.standardizedFileURL == item.url.deletingLastPathComponent().standardizedFileURL {
                    pendingAction = action
                    isChoosingFolder = true
                } else {
                    isError = true
                    message = (error as? LocalizedError)?.errorDescription ?? "Operation failed."
                }
            }
        }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func resultRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}
