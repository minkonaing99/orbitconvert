import SwiftUI

struct AutomationRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AutomationRule
    let onSave: (AutomationRule) -> Void
    let onTest: (AutomationRule) -> Void

    init(rule: AutomationRule, onSave: @escaping (AutomationRule) -> Void,
         onTest: @escaping (AutomationRule) -> Void) {
        _draft = State(initialValue: rule)
        self.onSave = onSave
        self.onTest = onTest
    }

    private var validation: String? {
        do { try draft.validate(); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Rule").font(.title2.bold())
            Text("Conditions choose the files. Actions run from top to bottom.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Rule name", text: value(\.name))
                Toggle("Enabled", isOn: value(\.isEnabled)).toggleStyle(.switch)
            }
            HStack {
                Picker("Scope", selection: value(\.includeSubfolders)) {
                    Text("Current folder").tag(false)
                    Text("Include subfolders").tag(true)
                }
                Picker("Match", selection: value(\.matchAll)) {
                    Text("All conditions").tag(true)
                    Text("Any condition").tag(false)
                }
            }
            HStack {
                Text("Conditions").font(.headline)
                Spacer()
                Button("Add condition", systemImage: "plus") {
                    var next = draft
                    next.conditions = draft.conditions + [AutomationCondition()]
                    draft = next
                }.disabled(draft.conditions.count >= 32)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(draft.conditions) { condition in conditionRow(condition) }
                }
            }.frame(height: 100)
            Text("Text matches ignore case. Dates: yyyy-MM-dd. Size uses decimal MB.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Actions").font(.headline)
                Text("Drag to reorder").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Add action") {
                    ForEach(AutomationActionKind.allCases) { kind in
                        Button(kind.rawValue) {
                            var next = draft
                            next.actions = draft.actions + [AutomationAction(kind: kind)]
                            draft = next
                        }
                    }
                }.disabled(draft.actions.count >= 16)
            }
            List {
                ForEach(draft.actions) { action in
                    HStack(alignment: .top, spacing: 8) {
                        AutomationActionEditor(action: actionBinding(action))
                        VStack(spacing: 8) {
                            Button("Move action up", systemImage: "arrow.up") { move(action.id, offset: -1) }
                                .disabled(draft.actions.first?.id == action.id)
                            Button("Move action down", systemImage: "arrow.down") { move(action.id, offset: 1) }
                                .disabled(draft.actions.last?.id == action.id)
                            Button("Remove action", systemImage: "minus.circle") {
                                var next = draft
                                next.actions = draft.actions.filter { $0.id != action.id }
                                draft = next
                            }.disabled(draft.actions.count == 1)
                        }.labelStyle(.iconOnly).buttonStyle(.borderless)
                    }.padding(.vertical, 6)
                }
                .onMove { source, destination in
                    var next = draft
                    next.actions.move(fromOffsets: source, toOffset: destination)
                    draft = next
                }
            }.listStyle(.inset).frame(minHeight: 150)
            if let validation {
                Text(validation).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Test Rule") { onTest(draft) }.disabled(validation != nil)
                Text("Preview only; no files change.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(validation != nil)
            }
        }.padding(20).frame(width: 760, height: 620)
    }

    private func conditionRow(_ condition: AutomationCondition) -> some View {
        HStack {
            Picker("Field", selection: Binding(get: { condition.field }, set: { field in
                var next = condition
                next.field = field
                next.comparison = .equals
                next.value = field == .category ? "Image" : ""
                replace(next)
            })) {
                ForEach(AutomationField.allCases.filter { $0 != .typeIdentifier || condition.field == .typeIdentifier }) {
                    Text($0.rawValue).tag($0)
                }
            }.frame(width: 160)
            Picker("Comparison", selection: Binding(get: { condition.comparison }, set: {
                var next = condition; next.comparison = $0; replace(next)
            })) {
                ForEach(condition.field.comparisons) { Text($0.rawValue).tag($0) }
            }.frame(width: 150)
            if condition.field == .category {
                Picker("Category", selection: conditionValue(condition)) {
                    ForEach(["Image", "PDF", "Video", "Audio", "Document", "Archive", "Other"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
            } else {
                TextField(condition.field.dated ? "yyyy-MM-dd" : "Value", text: conditionValue(condition))
            }
            Button("Remove condition", systemImage: "minus.circle") {
                var next = draft
                next.conditions = draft.conditions.filter { $0.id != condition.id }
                draft = next
            }.labelStyle(.iconOnly).disabled(draft.conditions.count == 1)
        }.labelsHidden()
    }

    private func conditionValue(_ condition: AutomationCondition) -> Binding<String> {
        Binding(get: { condition.value }, set: { value in
            var next = condition; next.value = value; replace(next)
        })
    }

    private func replace(_ condition: AutomationCondition) {
        var next = draft
        next.conditions = draft.conditions.map { $0.id == condition.id ? condition : $0 }
        draft = next
    }

    private func value<T>(_ keyPath: WritableKeyPath<AutomationRule, T>) -> Binding<T> {
        Binding(get: { draft[keyPath: keyPath] }, set: { value in
            var next = draft; next[keyPath: keyPath] = value; draft = next
        })
    }

    private func actionBinding(_ action: AutomationAction) -> Binding<AutomationAction> {
        Binding(get: { draft.actions.first { $0.id == action.id } ?? action }, set: { value in
            var next = draft
            next.actions = draft.actions.map { $0.id == action.id ? value : $0 }
            draft = next
        })
    }

    private func move(_ id: UUID, offset: Int) {
        guard let index = draft.actions.firstIndex(where: { $0.id == id }),
              draft.actions.indices.contains(index + offset) else { return }
        var next = draft
        next.actions.swapAt(index, index + offset)
        draft = next
    }
}
