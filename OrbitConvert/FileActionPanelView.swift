import AppKit
import SwiftUI

struct FileActionPanelView: View {
    let file: FileItem
    let actions: [FileAction]
    let isEnabled: Bool
    let returnSelectsFirstAction: Bool
    let onSelect: (FileAction) -> Void
    let onDismiss: () -> Void
    let onFocusChanged: (String?) -> Void
    @FocusState private var focusedActionID: String?

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]
    private var conversions: [FileAction] { actions.filter { $0.category == .conversion } }
    private var tools: [FileAction] { actions.filter { $0.category == .tool } }
    private var primaryActionID: String? { (conversions.first ?? tools.first)?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Convert", actions: conversions)
                    section("Tools", actions: tools)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .padding(16)
        .frame(maxWidth: 420)
        .frame(maxHeight: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onExitCommand(perform: onDismiss)
        .onAppear {
            if returnSelectsFirstAction {
                focusedActionID = primaryActionID
                onFocusChanged(primaryActionID)
            }
        }
        .onChange(of: focusedActionID) { _, id in onFocusChanged(id) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for \(file.fileName)")
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let thumbnail = NSImage(data: file.thumbnailData) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(file.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(file.contentTypeName) · \(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func section(_ title: String, actions: [FileAction]) -> some View {
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(actions) { action in
                        actionButton(action)
                    }
                }
            }
        }
    }

    private func actionButton(_ action: FileAction) -> some View {
        Button { onSelect(action) } label: {
            Label(action.title, systemImage: action.symbolName)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityLabel("\(action.title) for \(file.fileName)")
        .disabled(!isEnabled)
        .focused($focusedActionID, equals: action.id)
    }
}
