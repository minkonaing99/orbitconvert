import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var files: [FileItem] = []
    @State private var selectedURLs: Set<URL> = []
    @State private var issues: [FileIntakeIssue] = []
    @State private var inspectionTask: Task<Void, Never>?
    @State private var pendingInspections = 0
    @State private var isProcessing = false

    init(files: [FileItem] = []) {
        _files = State(initialValue: files)
        _selectedURLs = State(initialValue: Set(files.map(\.url)))
    }

    private var selectedFiles: [FileItem] { files.filter { selectedURLs.contains($0.url) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if files.isEmpty {
                emptyState
            } else {
                HStack {
                    Text("Files").font(.title2.weight(.semibold))
                    Spacer()
                    Button(selectedURLs.count == files.count ? "Deselect All" : "Select All") {
                        selectedURLs = selectedURLs.count == files.count ? [] : Set(files.map(\.url))
                    }
                    .buttonStyle(.borderless)
                    .disabled(isProcessing)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(files) { file in
                            fileRow(file)
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .frame(height: min(CGFloat(files.count) * 61, 240))
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Text("\(selectedFiles.count) selected · \(ByteCountFormatter.string(fromByteCount: selectedFiles.reduce(0) { $0 + $1.fileSize }, countStyle: .file))")
                    Spacer()
                    Text("Drop more files anywhere").foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                ScrollView {
                    if let first = selectedFiles.first {
                        ConversionControlsView(file: first, selection: selectedFiles,
                            onBusyChanged: { isProcessing = $0 })
                    } else {
                        Text("Select files to see available actions.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
            if pendingInspections > 0 { ProgressView("Inspecting files...").controlSize(.small) }
            if !issues.isEmpty {
                DisclosureGroup("Could not import \(issues.count) item(s)") {
                    ForEach(issues) { issue in
                        Text("\(issue.name): \(issue.message)").font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { importDrop($0) }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 2)
                    .padding(8).allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { isImporting = true } label: { Label("Add Files", systemImage: "plus") }
                    .keyboardShortcut("o")
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                issues = []
                accept(urls)
            case .failure:
                issues = issues + [FileIntakeIssue(name: "Selection", message: "The selected files could not be opened.")]
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 42, weight: .ultraLight)).accessibilityHidden(true)
            Text("Drop files here").font(.title2.weight(.semibold))
            Text("Convert images and PDFs, or reduce their file size.")
                .foregroundStyle(.secondary)
            Button("Choose Files") { isImporting = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func fileRow(_ file: FileItem) -> some View {
        HStack(spacing: 12) {
            Toggle("Select \(file.fileName)", isOn: Binding(
                get: { selectedURLs.contains(file.url) },
                set: { value in
                    selectedURLs = value ? selectedURLs.union([file.url]) : selectedURLs.subtracting([file.url])
                }))
                .labelsHidden().toggleStyle(.checkbox)
            if let image = NSImage(data: file.thumbnailData) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: 40, height: 40).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(file.fileName).lineLimit(1).truncationMode(.middle)
                Text(file.contentTypeName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
                .font(.caption).foregroundStyle(.secondary).fixedSize()
            Button {
                files = files.filter { $0.url != file.url }
                selectedURLs = selectedURLs.subtracting([file.url])
            } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help("Remove from list")
                .accessibilityLabel("Remove \(file.fileName) from list")
        }
        .frame(minHeight: 40)
        .padding(10)
        .disabled(isProcessing)
        .contextMenu {
            Button("Move Up") { reorderPDF(file.url, by: -1) }.disabled(isProcessing || !file.isPDF)
            Button("Move Down") { reorderPDF(file.url, by: 1) }.disabled(isProcessing || !file.isPDF)
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

    private func importDrop(_ providers: [NSItemProvider]) -> Bool {
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
            accept(urls)
        }
        return true
    }

    private func accept(_ urls: [URL]) {
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
            if !isProcessing { selectedURLs = selectedURLs.union(inspected.files.map(\.url)) }
            issues = issues + intake.issues + inspected.issues
            pendingInspections -= 1

        }
    }
}

#Preview { ContentView() }
