import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConversionControlsView: View {
    let file: FileItem
    let selection: [FileItem]
    let autoOpenPanel: Bool
    let onFloatingOpened: () -> Void
    let onBusyChanged: (Bool) -> Void

    @AppStorage("defaultCompressionPreset") private var defaultPreset = CompressionPreset.balanced.rawValue
    @AppStorage("jpegExportQuality") private var jpegQuality = 0.90
    @AppStorage("removeMetadata") private var stripMetadata = false
    @AppStorage("pdfImageDPI") private var pdfDPI = 150
    @State private var strongerPDFCompression = false
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
    @State private var worker: Task<Result<[SelectionActionEntry], Error>, Never>?
    @State private var entries: [SelectionActionEntry] = []
    @State private var selectedActionID = ""
    @State private var optionsExpanded = false
    @State private var customDirectory: URL?
    @State private var isSelectingOutput = false
    @State private var wasCancelled = false
    @State private var markdownImageFolder: URL?
    @State private var isSelectingImages = false
    @State private var markdownPDFStyle = MarkdownPDFStyle()
    @State private var targetBytes: Int64 = 2_000_000
    @State private var isShowingTargetSize = false
    @State private var resizeOptions = ResizeOptions()
    @State private var resizeCompression = CompressionPreset.balanced
    @State private var isShowingResize = false

    private var actions: [FileAction] { FileAction.common(for: selection) }
    private var preset: CompressionPreset {
        get { CompressionPreset(rawValue: defaultPreset) ?? .balanced }
        nonmutating set { defaultPreset = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionBar
                .disabled(isConverting)
            if !actions.isEmpty {
                DisclosureGroup("Options", isExpanded: $optionsExpanded) { options.padding(.top, 8) }
                    .disabled(isConverting)
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
                    Label(wasCancelled ? "Operation Cancelled" : isError ? "Some Files Could Not Be Processed" : lastAction?.kind == .compress ? "Optimization Finished" : lastAction?.category == .tool ? "Action Complete" : "Conversion Complete",
                          systemImage: isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isError ? .red : .primary)
                    Text(message).font(.caption)
                    if entries.count > 1 {
                        if lastAction?.kind == .compress || lastAction?.kind == .resize || lastAction?.kind == .compressToSize {
                            let completed = entries.filter { $0.report != nil }
                            let original = completed.reduce(Int64(0)) { $0 + $1.originalBytes }
                            let optimized = completed.reduce(Int64(0)) { $0 + ($1.report?.compression?.outputBytes ?? $1.originalBytes) }
                            let reduction = original > 0 ? Double(original - optimized) / Double(original) * 100 : 0
                            resultRow("Original", value: size(original))
                            resultRow("Optimized", value: size(optimized))
                            resultRow("Saved", value: size(original - optimized))
                            resultRow("Reduction", value: "\(reduction.formatted(.number.precision(.fractionLength(0))))%")
                        }
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.fileName).lineLimit(1).truncationMode(.middle)
                                Text(entry.errorMessage ?? entry.report?.message ?? "")
                                    .foregroundStyle(entry.errorMessage == nil ? Color.secondary : .red)
                            }.font(.caption)
                        }
                    }
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Text(customDirectory.map { "Output: " + $0.lastPathComponent } ??
                     (selection.count > 1 ? "Output: Choose a folder when prompted" : "Output: Beside original"))
                    .lineLimit(1).truncationMode(.middle)
                Button("Change...") { isSelectingOutput = true }
                if customDirectory != nil { Button("Reset") { customDirectory = nil } }
            }
            .disabled(isConverting)
            Text("Original files are kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { selection in
            guard let action = pendingAction else { return }
            pendingAction = nil
            onBusyChanged(false)
            switch selection {
            case .success(let folder):
                customDirectory = folder
                process(action, in: folder, resizeConfirmed: action.kind == .resize, targetConfirmed: action.kind == .compressToSize)
            case .failure: message = "No output folder was selected."
            }
        }
        .fileImporter(isPresented: $isSelectingOutput, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { customDirectory = folder }
        }
        .fileImporter(isPresented: $isSelectingImages, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { markdownImageFolder = folder }
        }
        .sheet(isPresented: $isShowingTargetSize) {
            TargetSizeOptionsView(count: selection.count,
                onCancel: { isShowingTargetSize = false },
                onRun: { bytes in
                    targetBytes = bytes
                    isShowingTargetSize = false
                    process(FileAction(.compressToSize), in: customDirectory, targetConfirmed: true)
                })
        }
        .sheet(isPresented: $isShowingResize) {
            ResizeOptionsView(files: selection, options: $resizeOptions,
                              compressionPreset: $resizeCompression,
                              onCancel: { isShowingResize = false },
                              onRun: {
                                  isShowingResize = false
                                  process(FileAction(.resize), in: customDirectory, resizeConfirmed: true)
                              })
        }
        .onDisappear { floatingController?.dismiss(); worker?.cancel() }
        .onChange(of: selection.map(\.url)) { _, _ in floatingController?.dismiss() }
        .task(id: autoOpenPanel) {
            guard autoOpenPanel else { return }
            showFloatingPanel()
            onFloatingOpened()
        }
    }

    private var conversionActions: [FileAction] { actions.filter { $0.category == .conversion } }
    private var chosenConversion: FileAction? {
        conversionActions.first { $0.id == selectedActionID } ?? conversionActions.first
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if actions.contains(FileAction(.compress)) {
                Button(selection.count > 1 ? "Compress Selected" : "Compress") {
                    process(FileAction(.compress), in: customDirectory)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            if let chosenConversion {
                HStack {
                    Picker("Convert to", selection: Binding(
                        get: { self.chosenConversion?.id ?? "" }, set: { selectedActionID = $0 })) {
                        ForEach(conversionActions) { action in Text(action.title).tag(action.id) }
                    }
                    .frame(maxWidth: 230)
                    Button(chosenConversion.kind == .imagePDF && selection.count > 1 ? "Create PDF" : "Convert") {
                        process(chosenConversion, in: customDirectory)
                    }
                }
            }
            let tools = actions.filter { $0.category == .tool && $0.kind != .compress }
            if !tools.isEmpty {
                Menu("Tools") {
                    ForEach(tools) { action in
                        Button(action.title) {
                            if action.kind == .extractPages { optionsExpanded = true }
                            else { process(action, in: customDirectory) }
                        }
                    }
                    if actions.contains(FileAction(.extractPages)) {
                        Button("Extract All Pages") {
                            pageSelection = "all"
                            process(FileAction(.extractPages), in: customDirectory)
                        }
                    }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selection.allSatisfy(\.isMarkdown) {
                HStack {
                    Text(markdownImageFolder.map { "Image folder: " + $0.lastPathComponent } ?? "Images: Alt text only")
                        .lineLimit(1).truncationMode(.middle)
                    Button("Allow Local Images...") { isSelectingImages = true }
                    if markdownImageFolder != nil { Button("Reset") { markdownImageFolder = nil } }
                }
                Text("Choose the folder containing your notes and images. Only relative image paths inside that folder are read; remote images and symlinks are skipped.")
                    .font(.caption).foregroundStyle(.secondary)
                if chosenConversion?.kind == .markdownPDF {
                    Toggle("US Letter page", isOn: $markdownPDFStyle.useLetter)
                    Toggle("Serif body font", isOn: $markdownPDFStyle.useSerif)
                    Stepper("Body size: \(Int(markdownPDFStyle.bodySize)) pt", value: $markdownPDFStyle.bodySize, in: 8...24)
                    Stepper("Page margins: \(Int(markdownPDFStyle.margin)) pt", value: $markdownPDFStyle.margin, in: 20...90, step: 5)
                }
            }
            if chosenConversion?.kind == .pdfJPEG || chosenConversion?.kind == .convert(.jpeg) {
                HStack {
                    Text("JPEG export quality")
                    Slider(value: $jpegQuality, in: 0...1).frame(maxWidth: 180)
                    Text(jpegQuality.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                }
            }
            Toggle("Remove metadata", isOn: $stripMetadata)
            if actions.contains(FileAction(.compress)) {
                Picker("Compression", selection: Binding(get: { preset }, set: { preset = $0 })) {
                    ForEach(CompressionPreset.allCases.filter { $0 != .custom }) { Text($0.label).tag($0) }
                }.frame(maxWidth: 280)
                if selection.allSatisfy(\.isPDF) {
                    Toggle("Stronger PDF compression", isOn: $strongerPDFCompression)
                    Text("Downsamples embedded images and preserves supported web links and bookmarks. Forms, other annotations, signed/encrypted and tagged PDFs are excluded. Balanced: 150 DPI; Maximum: 100 DPI. Lossless uses the native backend.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if selection.allSatisfy({ $0.contentTypeIdentifier == UTType.png.identifier }) {
                    Text("PNG optimization is lossless. Maximum spends more time finding a smaller file.").foregroundStyle(.secondary)
                }
                if preset == .lossless && selection.contains(where: {
                    ConversionFormat.sourceFormat(for: $0.contentTypeIdentifier) == .jpeg
                }) {
                    Text("Lossless JPEG optimization is unavailable. Choose Balanced or Maximum.")
                        .foregroundStyle(.secondary)
                }
            }
            if file.isPDF && (chosenConversion?.kind == .pdfJPEG || chosenConversion?.kind == .pdfPNG) {
                Picker("Resolution", selection: $pdfDPI) {
                    ForEach([72, 100, 150, 200, 300], id: \.self) { Text("\($0) DPI").tag($0) }
                }.frame(maxWidth: 240)
            }
            if actions.contains(FileAction(.extractPages)) {
                HStack {
                    TextField("Pages: all, 4, or 4-7", text: $pageSelection)
                        .frame(maxWidth: 190).accessibilityLabel("Pages to extract")
                    Button("Extract Pages") { process(FileAction(.extractPages), in: customDirectory) }
                }
            }
            if chosenConversion?.kind == .imagePDF {
                Picker("PDF page size", selection: $pdfLayout) {
                    ForEach(PDFPageLayout.allCases) { Text($0.label).tag($0) }
                }.frame(maxWidth: 280)
            }
        }.font(.callout)
    }

    private func showFloatingPanel() {
        floatingController?.dismiss()
        let controller = FloatingActionPanelController(
            file: file, actions: actions,
            onSelect: { action in process(action, in: customDirectory) },
            onClose: { floatingController = nil }
        )
        floatingController = controller
        if !controller.show() { message = "No screen can display the floating panel." }
    }

    private func process(_ action: FileAction, in directory: URL?, resizeConfirmed: Bool = false, targetConfirmed: Bool = false) {
        guard !isConverting else { return }
        floatingController?.dismiss()
        if action.kind == .compressToSize && !targetConfirmed {
            isShowingTargetSize = true
            return
        }
        if action.kind == .resize && !resizeConfirmed {
            isShowingResize = true
            return
        }
        if selection.count > 1 && directory == nil {
            pendingAction = action
            onBusyChanged(true)
            isChoosingFolder = true
            return
        }
        isConverting = true
        onBusyChanged(true)
        entries = []
        isError = false
        wasCancelled = false
        lastAction = action
        message = nil
        compression = nil
        resultURLs = []
        progressText = "Preparing..."
        let files = selection
        let settings = FileActionSettings(targetBytes: targetBytes, resizeOptions: resizeOptions, markdownImageFolder: markdownImageFolder,
                                          markdownPDFStyle: markdownPDFStyle,
                                          strongerPDFCompression: strongerPDFCompression && preset != .lossless, jpegQuality: jpegQuality, stripMetadata: stripMetadata,
                                          compressionPreset: action.kind == .resize ? resizeCompression : preset, pdfDPI: pdfDPI,
                                          pdfLayout: pdfLayout, pageSelection: pageSelection)
        let (updates, continuation) = AsyncStream<String>.makeStream()
        Task { for await update in updates { progressText = update } }
        let job = Task.detached(priority: .userInitiated) {
            defer { continuation.finish() }
            do {
                let results = try await SelectionActionService().execute(action, files: files,
                                                directory: directory, settings: settings,
                                                progress: { continuation.yield($0) })
                return Result<[SelectionActionEntry], Error>.success(results)
            } catch { return Result<[SelectionActionEntry], Error>.failure(error) }
        }
        worker = job
        Task {
            let outcome = await job.value
            wasCancelled = job.isCancelled
            worker = nil
            isConverting = false
            onBusyChanged(false)
            progressText = nil
            switch outcome {
            case .success(let results):
                entries = results
                resultURLs = results.flatMap { $0.report?.outputURLs ?? [] }
                compression = results.count == 1 ? results.first?.report?.compression : nil
                isError = results.contains { $0.errorMessage != nil }
                message = results.count == 1 ? (results.first?.report?.message ?? results.first?.errorMessage)
                    : "\(results.count) of \(files.count) files processed."
                if results.isEmpty { message = "Operation cancelled." }
                if wasCancelled { message = "Cancelled after processing \(results.count) of \(files.count) files. Completed outputs were kept." }
            case .failure(let error):
                if error is CancellationError {
                    message = "Operation cancelled."
                } else if let conversionError = error as? ConversionError,
                          [.permissionDenied, .invalidDestination].contains(conversionError),
                          directory == nil {
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
