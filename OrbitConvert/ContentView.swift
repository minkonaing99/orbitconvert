import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var files: [FileItem] = []
    @State private var issues: [FileIntakeIssue] = []
    @State private var inspectionTask: Task<Void, Never>?
    @State private var pendingInspections = 0
    @State private var dropWindow: FloatingDropWindowController?
    @State private var pendingFloatingFileURL: URL?
    @State private var isChoosingBatchFolder = false
    @State private var batchTask: Task<BatchOptimizationResult, Never>?
    @State private var batchProgress: String?
    @State private var batchResult: BatchOptimizationResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppIdentity.name)
                    .font(.largeTitle.weight(.semibold))
                Text("Local file conversion starts here")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 42, weight: .ultraLight))
                    .accessibilityHidden(true)
                Text("Drop files here")
                    .font(.title2.weight(.medium))
                Button("Choose Files") { isImporting = true }
                    .buttonStyle(.borderedProminent)
                Button("Open Floating Drop Target") { toggleDropWindow() }
                    .accessibilityHint("Opens a small window that accepts files dragged from Finder")
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { importDrop($0) }

            if pendingInspections > 0 {
                ProgressView("Inspecting files...")
            }

            if files.count > 1 { batchControls }

            if !files.isEmpty || !issues.isEmpty {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if !files.isEmpty {
                                Text("Selected files")
                                    .font(.headline)
                                ForEach(files) { file in
                                    HStack(alignment: .top, spacing: 12) {
                                        if let preview = NSImage(data: file.thumbnailData) {
                                            Image(nsImage: preview)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 72, height: 72)
                                                .accessibilityHidden(true)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.fileName).fontWeight(.medium)
                                            Text("\(file.contentTypeName) · \(file.fileExtension.uppercased()) · \(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))")
                                                .foregroundStyle(.secondary)
                                            if let pages = file.pageCount {
                                                Text("\(pages) \(pages == 1 ? "page" : "pages")")
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                Text("\(file.pixelWidth) × \(file.pixelHeight) px")
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let created = file.creationDate {
                                                Text("Created \(created.formatted(date: .abbreviated, time: .omitted))")
                                                    .foregroundStyle(.secondary)
                                            }
                                            ConversionControlsView(
                                                file: file,
                                                selection: files,
                                                autoOpenFloating: pendingFloatingFileURL == file.url,
                                                onFloatingOpened: { pendingFloatingFileURL = nil }
                                            )
                                            if file.isPDF, files.filter(\.isPDF).count > 1 {
                                                HStack {
                                                    Button("Move Up") { reorderPDF(file.url, by: -1) }
                                                    Button("Move Down") { reorderPDF(file.url, by: 1) }
                                                }
                                                .font(.caption)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .id(file.url)
                                }
                            }
                            if !issues.isEmpty {
                                Text("Could not import")
                                    .font(.headline)
                                ForEach(issues) { issue in
                                    Label("\(issue.name): \(issue.message)", systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .onChange(of: pendingFloatingFileURL) { _, url in
                        if let url { scroll.scrollTo(url, anchor: .top) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(28)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                issues = []
                accept(urls)
            case .failure:
                issues = issues + [FileIntakeIssue(name: "Selection", message: "The selected files could not be opened.")]
            }
        }
        .fileImporter(isPresented: $isChoosingBatchFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let folder): optimizeBatch(in: folder)
            case .failure: batchProgress = "No output folder was selected."
            }
        }
        .onDisappear {
            dropWindow?.dismiss()
            batchTask?.cancel()
        }
    }

    private var batchControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Compress All Supported Files") { isChoosingBatchFolder = true }
                .disabled(batchTask != nil)
            if let batchProgress {
                HStack {
                    ProgressView(batchProgress).controlSize(.small)
                    if batchTask != nil { Button("Cancel") { batchTask?.cancel() } }
                }
            }
            if let batchResult {
                Text("\(batchResult.successCount) of \(batchResult.attemptedCount) processed · \(ByteCountFormatter.string(fromByteCount: batchResult.originalBytes, countStyle: .file)) to \(ByteCountFormatter.string(fromByteCount: batchResult.outputBytes, countStyle: .file)) · \(ByteCountFormatter.string(fromByteCount: batchResult.savingsBytes, countStyle: .file)) saved (\(batchResult.savingsPercentage.formatted(.number.precision(.fractionLength(0))))%)")
                    .font(.caption)
                if !batchResult.saved.isEmpty {
                    Button("Reveal Results in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(batchResult.saved.map(\.outputURL))
                    }
                }
                ForEach(batchResult.failures, id: \.fileName) { failure in
                    Text("\(failure.fileName): \(failure.message)").foregroundStyle(.red).font(.caption)
                }
            }
        }
    }

    private func optimizeBatch(in directory: URL) {
        let eligible = files.filter {
            $0.isPDF || [.jpeg, .png].contains(ConversionFormat.sourceFormat(for: $0.contentTypeIdentifier))
        }
        guard !eligible.isEmpty else { return }
        batchResult = nil
        batchProgress = "Preparing..."
        let (updates, continuation) = AsyncStream<String>.makeStream()
        Task { for await update in updates { batchProgress = update } }
        let preset = CompressionPreset(rawValue: UserDefaults.standard.string(forKey: "defaultCompressionPreset") ?? "") ?? .balanced
        let removeMetadata = UserDefaults.standard.bool(forKey: "removeMetadata")
        let job = Task.detached(priority: .userInitiated) {
            defer { continuation.finish() }
            return BatchOptimizationService().optimize(eligible, in: directory, preset: preset,
                removeMetadata: removeMetadata,
                progress: { current, total in continuation.yield("Optimizing \(current) of \(total)") })
        }
        batchTask = job
        Task {
            batchResult = await job.value
            batchTask = nil
            batchProgress = nil
        }
    }

    private func reorderPDF(_ url: URL, by direction: Int) {
        let pdfIndices = files.indices.filter { files[$0].isPDF }
        guard let current = pdfIndices.firstIndex(where: { files[$0].url == url }),
              pdfIndices.indices.contains(current + direction) else { return }
        var reordered = files
        reordered.swapAt(pdfIndices[current], pdfIndices[current + direction])
        files = reordered
    }

    private func toggleDropWindow() {
        if let dropWindow { dropWindow.dismiss(); return }
        let controller = FloatingDropWindowController(onDrop: { providers in
            let accepted = importDrop(providers, openFloatingOnImport: true)
            if accepted { DispatchQueue.main.async { dropWindow?.dismiss() } }
            return accepted
        }, onClose: { dropWindow = nil })
        dropWindow = controller
        if !controller.show() {
            dropWindow = nil
            issues = issues + [FileIntakeIssue(name: "Floating drop target", message: "No screen can display the drop target.")]
        }
    }

    private func importDrop(_ providers: [NSItemProvider], openFloatingOnImport: Bool = false) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        issues = []
        let group = DispatchGroup()
        let lock = NSLock()
        var loaded = Array<URL?>(repeating: nil, count: fileProviders.count)
        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                lock.lock()
                loaded[index] = object as? URL
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = loaded.compactMap { $0 }
            for _ in (0..<(fileProviders.count - urls.count)) {
                issues = issues + [FileIntakeIssue(name: "Dropped item", message: "This file could not be opened.")]
            }
            accept(urls, openFloatingOnImport: openFloatingOnImport)
        }
        return true
    }

    private func accept(_ urls: [URL], openFloatingOnImport: Bool = false) {
        let previous = inspectionTask
        pendingInspections += 1
        inspectionTask = Task {
            await previous?.value
            let intakeService = FileIntakeService()
            let typeService = FileTypeService()
            let (intake, inspected) = await Task.detached(priority: .userInitiated) {
                let intake = intakeService.inspect(urls)
                let inspected = typeService.inspect(intake.files.map(\.url))
                return (intake, inspected)
            }.value
            files = (inspected.files + files).reduce(into: [FileItem]()) { unique, file in
                if !unique.contains(where: { $0.url == file.url }) { unique.append(file) }
            }
            issues = issues + intake.issues + inspected.issues
            pendingInspections -= 1
            if openFloatingOnImport,
               let first = inspected.files.first(where: { !FileAction.available(for: $0, selection: inspected.files).isEmpty }) {
                pendingFloatingFileURL = first.url
            } else if openFloatingOnImport, !issues.isEmpty {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

#Preview {
    ContentView()
}
