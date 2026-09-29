import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var files: [FileItem] = []
    @State private var issues: [FileIntakeIssue] = []
    @State private var inspectionTask: Task<Void, Never>?
    @State private var pendingInspections = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppIdentity.name)
                    .font(.largeTitle.weight(.semibold))
                Text("Local image conversion starts here")
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
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: importDrop)

            if pendingInspections > 0 {
                ProgressView("Inspecting images...")
            }

            if !files.isEmpty || !issues.isEmpty {
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
                                        Text("\(file.pixelWidth) × \(file.pixelHeight) px")
                                            .foregroundStyle(.secondary)
                                        if let created = file.creationDate {
                                            Text("Created \(created.formatted(date: .abbreviated, time: .omitted))")
                                                .foregroundStyle(.secondary)
                                        }
                                        Text("Available outputs: \(file.supportedConversions.map(\.label).joined(separator: ", "))")
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
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
    }

    private func importDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        issues = []
        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await droppedURL(from: provider) {
                    urls = urls + [url]
                } else {
                    issues = issues + [FileIntakeIssue(name: "Dropped item", message: "This file could not be opened.")]
                }
            }
            accept(urls)
        }
        return true
    }

    private func droppedURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                continuation.resume(returning: object as? URL)
            }
        }
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
            files = (files + inspected.files).reduce(into: [FileItem]()) { unique, file in
                if !unique.contains(where: { $0.url == file.url }) { unique.append(file) }
            }
            issues = issues + intake.issues + inspected.issues
            pendingInspections -= 1
        }
    }
}

#Preview {
    ContentView()
}
