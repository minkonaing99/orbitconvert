import Foundation

// Starting points for common rules. Each call returns a new rule; the editor still requires Save,
// and Move templates require choosing a destination first.
nonisolated enum AutomationRuleTemplate: String, CaseIterable, Identifiable, Sendable {
    case screenshots, shrinkPhotos, tidyPDFs, sortImages, sortPDFs, sortArchives, sortDocuments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots: "Screenshots: rename and compress"
        case .shrinkPhotos: "Large JPEG photos: make smaller copy"
        case .tidyPDFs: "PDFs: add date and compress"
        case .sortImages: "Sort downloads: images"
        case .sortPDFs: "Sort downloads: PDFs"
        case .sortArchives: "Sort downloads: archives"
        case .sortDocuments: "Sort downloads: documents"
        }
    }

    var menuTitle: String {
        switch self {
        case .sortImages: "Images"
        case .sortPDFs: "PDFs"
        case .sortArchives: "Archives"
        case .sortDocuments: "Documents and text files"
        default: title
        }
    }

    var isSorting: Bool { [.sortImages, .sortPDFs, .sortArchives, .sortDocuments].contains(self) }

    func makeRule() -> AutomationRule {
        AutomationRule(name: title, matchAll: true, conditions: conditions, actions: actions)
    }

    private var conditions: [AutomationCondition] {
        switch self {
        // macOS names screenshots "Screenshot ..." in English; edit the prefix for other languages.
        case .screenshots:
            [condition(.name, .startsWith, "Screenshot"), condition(.typeIdentifier, .equals, "public.png"),
             condition(.name, .notContains, "-optimized")]
        case .shrinkPhotos:
            [condition(.typeIdentifier, .equals, "public.jpeg"), condition(.width, .greater, "2560")]
        case .tidyPDFs, .sortPDFs: [condition(.category, .equals, "PDF")]
        case .sortImages: [condition(.category, .equals, "Image")]
        case .sortArchives: [condition(.category, .equals, "Archive")]
        case .sortDocuments: [condition(.category, .equals, "Document")]
        }
    }

    private var actions: [AutomationAction] {
        switch self {
        case .screenshots:
            [AutomationAction(kind: .rename, template: "'Screenshot'_{yyyy}-{MM}-{dd}_{HH}-{mm}-{ss}.{ext}"),
             AutomationAction(kind: .compress, replacement: .keepBoth)]
        case .shrinkPhotos: [AutomationAction(kind: .resize, width: 2560, height: 2560)]
        case .tidyPDFs:
            [AutomationAction(kind: .rename, template: "{yyyy}-{MM}-{dd}_{name}.{ext}"),
             AutomationAction(kind: .compress, replacement: .keepBoth)]
        case .sortImages, .sortPDFs, .sortArchives, .sortDocuments: [AutomationAction(kind: .move)]
        }
    }

    private func condition(_ field: AutomationField, _ comparison: AutomationComparison, _ value: String) -> AutomationCondition {
        AutomationCondition(field: field, comparison: comparison, value: value)
    }
}

extension AutomationRule {
    // Rules are first-match-wins; keep Move rules last so a new rule is not hidden behind a sort rule.
    static func inserting(_ rule: AutomationRule, into rules: [AutomationRule]) -> [AutomationRule] {
        if rules.contains(where: { $0.id == rule.id }) { return rules.map { $0.id == rule.id ? rule : $0 } }
        let moves = { (candidate: AutomationRule) in candidate.actions.contains { $0.kind == .move } }
        guard !moves(rule), let index = rules.firstIndex(where: moves) else { return rules + [rule] }
        var next = rules
        next.insert(rule, at: index)
        return next
    }
}
