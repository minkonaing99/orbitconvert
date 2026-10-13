import Foundation

nonisolated enum AutomationField: String, Codable, CaseIterable, Identifiable, Sendable {
    case name = "Filename", fileExtension = "Extension", category = "File category", size = "Size (MB)"
    case created = "Created date", modified = "Modified date", width = "Width (pixels)", height = "Height (pixels)"
    case tags = "Finder tags", text = "Document text", typeIdentifier = "File type"
    var id: String { rawValue }
    var numeric: Bool { [.size, .width, .height].contains(self) }
    var dated: Bool { self == .created || self == .modified }
    var comparisons: [AutomationComparison] {
        if self == .typeIdentifier { return [.equals, .notEquals] }
        return numeric || dated ? [.equals, .notEquals, .greater, .less] : [.equals, .notEquals, .contains, .notContains, .startsWith, .endsWith]
    }
}

nonisolated enum AutomationComparison: String, Codable, CaseIterable, Identifiable, Sendable {
    case equals = "is", notEquals = "is not", contains = "contains", notContains = "does not contain"
    case startsWith = "starts with", endsWith = "ends with", greater = "is greater than", less = "is less than"
    var id: String { rawValue }
}

nonisolated struct AutomationCondition: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var field: AutomationField = .fileExtension
    var comparison: AutomationComparison = .equals
    var value = "png"
}

nonisolated enum AutomationActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case rename = "Rename", move = "Move to folder", copy = "Copy to folder", compress = "Compress"
    case convert = "Convert image", resize = "Resize image", removeMetadata = "Remove metadata"
    var id: String { rawValue }
}

nonisolated struct AutomationAction: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: AutomationActionKind = .rename
    var template = "yyyy-MM-dd_{name}_{i}.{ext}"
    var destinationBookmark: Data?
    var destinationName = "Choose a folder"
    var preset: CompressionPreset = .balanced
    var replacement: ReplacementBehavior = .keepBoth
    // Optional so rules saved before palette support still decode (missing means Off).
    var palette: PaletteLevel?
    var format = "jpeg"
    var width = 1920
    var height = 1080
    var quality = 0.9
}

nonisolated struct AutomationRule: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name = "New rule"
    var isEnabled = true
    var includeSubfolders = false
    var matchAll = true
    var conditions: [AutomationCondition] = [AutomationCondition()]
    var actions: [AutomationAction] = [AutomationAction()]

    func duplicated() -> Self {
        var copy = self
        copy.id = UUID()
        copy.name += " copy"
        return copy
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              (1...32).contains(conditions.count), (1...16).contains(actions.count) else {
            throw AutomationError.invalid("Give the rule a name, 1-32 conditions, and 1-16 actions.")
        }
        for condition in conditions {
            guard condition.field.comparisons.contains(condition.comparison),
                  !condition.value.isEmpty, condition.value.count <= 2_000 else {
                throw AutomationError.invalid("Enter a valid value for each condition.")
            }
            if condition.field.numeric {
                guard let number = Double(condition.value), number.isFinite, number >= 0 else {
                    throw AutomationError.invalid("Enter a nonnegative number for size or dimensions.")
                }
            }
            if condition.field.dated, AutomationConditionService.date(condition.value) == nil {
                throw AutomationError.invalid("Enter dates as yyyy-MM-dd.")
            }
        }
        for action in actions {
            if action.kind == .rename { _ = try AutomationRenameTemplate(action.template) }
            if [.move, .copy].contains(action.kind), action.destinationBookmark == nil {
                throw AutomationError.invalid("Choose a destination for every Move or Copy action.")
            }
            guard action.preset != .custom, action.quality.isFinite, (0...1).contains(action.quality),
                  (1...100_000).contains(action.width), (1...100_000).contains(action.height),
                  ["jpeg", "png", "heic", "tiff", "pdf"].contains(action.format) else {
                throw AutomationError.invalid("Check compression, format and image dimensions.")
            }
        }
    }
}

nonisolated enum AutomationError: LocalizedError, Sendable {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}
