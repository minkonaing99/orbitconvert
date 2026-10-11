import SwiftUI

struct AutomationRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var folder: WatchedFolder
    @State private var editing: AutomationRule?
    @State private var testing: AutomationRule?
    @State private var showRunPreview = false
    var canRun: Bool
    let onSave: (WatchedFolder) -> Void
    let onRun: ([AutomationPreviewItem]) -> Void

    init(folder: WatchedFolder, canRun: Bool = true, onSave: @escaping (WatchedFolder) -> Void,
         onRun: @escaping ([AutomationPreviewItem]) -> Void) {
        _folder = State(initialValue: folder)
        self.canRun = canRun
        self.onSave = onSave
        self.onRun = onRun
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Folder Automation").font(.title2.bold())
            Text(folder.displayName).font(.headline).textSelection(.enabled)
            Text("New files use the first matching rule, from top to bottom. Drag rules to change their priority.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("Rules").font(.headline)
                Spacer()
                Button("Add Rule", systemImage: "plus") { editing = AutomationRule() }
            }
            if folder.effectiveRules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle").font(.largeTitle).accessibilityHidden(true)
                    Text("No rules yet").font(.headline)
                    Text("Add a rule to rename, organize, or optimize new files.")
                        .foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(folder.effectiveRules) { rule in ruleRow(rule) }
                    .onMove { source, destination in
                        var rules = folder.effectiveRules
                        rules.move(fromOffsets: source, toOffset: destination)
                        save(rules)
                    }
                }.listStyle(.inset)
            }
            Text("Changes apply to future arrivals. Run Now previews existing files before making changes.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Run Now...") { showRunPreview = true }
                    .disabled(!canRun || !folder.effectiveRules.contains { $0.isEnabled })
                if !canRun { Text("Resume watching to run existing files.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 680, height: 520)
        .sheet(item: $editing) { rule in
            AutomationRuleEditor(rule: rule, onSave: saveRule, onTest: { testing = $0 })
                .sheet(item: $testing) { rule in
                    AutomationPreviewView(folder: folder, rule: rule)
                }
        }
        .sheet(isPresented: $showRunPreview) {
            AutomationPreviewView(folder: folder, onRun: onRun)
        }
    }

    private func ruleRow(_ rule: AutomationRule) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle(rule.name, isOn: Binding(get: { rule.isEnabled }, set: { enabled in
                var next = rule
                next.isEnabled = enabled
                saveRule(next)
            })).labelsHidden().toggleStyle(.switch).controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name).font(.headline)
                Text("\(rule.conditions.count) conditions, \(rule.actions.count) actions" +
                     (rule.includeSubfolders ? " - includes subfolders" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text(rule.actions.map { $0.kind.rawValue }.joined(separator: " > "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("Edit") { editing = rule }
            Menu {
                Button("Duplicate") { editing = rule.duplicated() }
                Button("Move Up") { move(rule.id, offset: -1) }
                    .disabled(folder.effectiveRules.first?.id == rule.id)
                Button("Move Down") { move(rule.id, offset: 1) }
                    .disabled(folder.effectiveRules.last?.id == rule.id)
                Divider()
                Button("Delete Rule", role: .destructive) {
                    save(folder.effectiveRules.filter { $0.id != rule.id })
                }
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("Options for \(rule.name)")
            }.menuStyle(.borderlessButton).frame(width: 28)
        }.padding(.vertical, 8)
    }

    private func saveRule(_ rule: AutomationRule) {
        let rules = folder.effectiveRules
        save(rules.contains { $0.id == rule.id }
             ? rules.map { $0.id == rule.id ? rule : $0 }
             : rules + [rule])
    }

    private func save(_ rules: [AutomationRule]) {
        var next = folder
        next.rules = rules
        folder = next
        onSave(next)
    }

    private func move(_ id: UUID, offset: Int) {
        var rules = folder.effectiveRules
        guard let index = rules.firstIndex(where: { $0.id == id }),
              rules.indices.contains(index + offset) else { return }
        rules.swapAt(index, index + offset)
        save(rules)
    }
}
