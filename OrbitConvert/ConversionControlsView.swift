import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConversionControlsView: View {
    let file: FileItem
    let selection: [FileItem]
    let autoOpenFloating: Bool
    let onFloatingOpened: () -> Void

    @AppStorage("defaultCompressionPreset") private var defaultPreset = CompressionPreset.balanced.rawValue
    @AppStorage("jpegExportQuality") private var jpegQuality = 0.90
    @AppStorage("removeMetadata") private var stripMetadata = false
    @AppStorage("pdfImageDPI") private var pdfDPI = 150
    @State private var pdfLayout = PDFPageLayout.fit
    @State private var pageSelection = "all"
    @State private var isConverting = false
    @State private var isChoosingFolder = false
    @State private var isShowingRadial = false
    @State private var floatingController: FloatingRadialWindowController?
    @State private var pendingAction: FileAction?
    @State private var message: String?
    @State private var isError = false
    @State private var resultURLs: [URL] = []
    @State private var compression: CompressionResult?
    @State private var progressText: String?
    @State private var worker: Task<Result<FileActionReport, Error>, Never>?

    private var actions: [FileAction] { FileAction.available(for: file, selection: selection) }
    private var preset: CompressionPreset {
        get { CompressionPreset(rawValue: defaultPreset) ?? .balanced }
        nonmutating set { defaultPreset = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Actions").foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(actions) { action in
                            Button(action.title) { process(action, in: file.url.deletingLastPathComponent()) }
                                .disabled(isConverting)
                                .accessibilityLabel("\(action.title) for \(file.fileName)")
                        }
                    }
                }
                Button("Radial Menu") { isShowingRadial.toggle() }
                    .disabled(isConverting || actions.isEmpty)
                Button("Floating Menu") { showFloatingMenu() }
                    .disabled(isConverting || actions.isEmpty)
            }
            if isShowingRadial {
                RadialMenuView(file: file, actions: actions) { action in
                    isShowingRadial = false
                    process(action, in: file.url.deletingLastPathComponent())
                } onDismiss: { isShowingRadial = false }
            }
            options
            if isConverting {
                HStack {
                    ProgressView(progressText ?? "Processing \(file.fileName)...")
                        .controlSize(.small)
                    Button("Cancel") { worker?.cancel() }
                }
            }
            if let message {
                HStack(spacing: 8) {
                    Text(message).foregroundStyle(isError ? .red : .secondary)
                    if !resultURLs.isEmpty {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(resultURLs)
                        }
                    }
                }
                .font(.caption)
            }
            if let compression {
                Text("Original \(size(compression.originalBytes))  Optimized \(size(compression.outputBytes))  Saved \(size(compression.savingsBytes)) (\(compression.savingsPercentage.formatted(.number.precision(.fractionLength(0))))%)")
                    .font(.caption)
                    .accessibilityLabel("Saved \(size(compression.savingsBytes)), \(compression.savingsPercentage.formatted(.number.precision(.fractionLength(0)))) percent")
            }
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
        .task(id: autoOpenFloating) {
            guard autoOpenFloating else { return }
            showFloatingMenu()
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

    private func showFloatingMenu() {
        isShowingRadial = false
        floatingController?.dismiss()
        let controller = FloatingRadialWindowController(
            file: file, actions: actions,
            onSelect: { action in process(action, in: file.url.deletingLastPathComponent()) },
            onClose: { floatingController = nil }
        )
        floatingController = controller
        if !controller.show() { isShowingRadial = true }
    }

    private func process(_ action: FileAction, in directory: URL) {
        guard !isConverting else { return }
        isShowingRadial = false
        floatingController?.dismiss()
        isConverting = true
        isError = false
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
}
