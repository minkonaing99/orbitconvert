import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var files: [ImportedFile] = []
    @State private var issues: [FileIntakeIssue] = []

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

            if !files.isEmpty || !issues.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !files.isEmpty {
                            Text("Selected files")
                                .font(.headline)
                            ForEach(files) { file in
                                Label(file.name, systemImage: "photo")
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                Task { @MainActor in
                    if let url = object as? URL {
                        accept([url])
                    } else {
                        issues = issues + [FileIntakeIssue(name: "Dropped item", message: "This file could not be opened.")]
                    }
                }
            }
        }
        return true
    }

    private func accept(_ urls: [URL]) {
        let result = FileIntakeService().inspect(urls)
        files = (files + result.files).reduce(into: [ImportedFile]()) { unique, file in
            if !unique.contains(where: { $0.url == file.url }) { unique.append(file) }
        }
        issues = issues + result.issues
    }
}

#Preview {
    ContentView()
}
