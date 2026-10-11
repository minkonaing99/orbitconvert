import SwiftUI

struct AutomationPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let folder: WatchedFolder
    var rule: AutomationRule? = nil
    var onRun: (([AutomationPreviewItem]) -> Void)? = nil
    @State private var items: [AutomationPreviewItem] = []
    @State private var loading = true
    @State private var issue: String?

    private var eligible: [AutomationPreviewItem] {
        items.filter { $0.rule != nil && $0.issue == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(rule == nil ? "Preview Existing Files" : "Test Rule").font(.title2.bold())
            Text(rule?.name ?? folder.displayName).font(.headline)
            Text("This preview does not change files. Names may change if another file arrives before the run.")
                .font(.callout).foregroundStyle(.secondary)
            if loading {
                ProgressView("Checking files...").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let issue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                Text("No files found in this rule's scope.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.url.lastPathComponent).font(.headline).textSelection(.enabled)
                        Text(item.rule?.name ?? "No matching rule")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(item.summary).font(.callout).textSelection(.enabled)
                        if let issue = item.issue {
                            Label(issue, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }.padding(.vertical, 6)
                }.listStyle(.inset)
            }
            if !loading && issue == nil {
                Text("\(eligible.count) of \(items.count) files ready" +
                     (onRun == nil ? ". Test only; no actions will run." : ". Other files will be skipped."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Spacer()
                Button(onRun == nil ? "Done" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if let onRun {
                    Button("Run \(eligible.count) Files") {
                        onRun(eligible)
                        dismiss()
                    }.keyboardShortcut(.defaultAction)
                        .disabled(loading || issue != nil || eligible.isEmpty)
                }
            }
        }
        .padding(20).frame(width: 700, height: 520)
        .task {
            do {
                let result = try await AutomationPreviewService.preview(folder: folder, rule: rule)
                guard !Task.isCancelled else { return }
                items = result
            } catch {
                guard !Task.isCancelled else { return }
                issue = error.localizedDescription
            }
            loading = false
        }
    }
}
