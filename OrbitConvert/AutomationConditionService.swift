import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

nonisolated struct AutomationFileFacts: Sendable {
    let url: URL
    let fingerprint: FileFingerprint
    let creationDate: Date?
    let modificationDate: Date?
    let typeIdentifier: String
    let category: String
    let width: Int?
    let height: Int?
    let tags: [String]
    let text: String?
    let textIssue: String?

    static func read(_ url: URL, includeText: Bool = false) throws -> Self {
        guard url.isFileURL, WatchFilePolicy.isEligibleFile(url, allowed: nil) else { throw WatchError.unavailableFile }
        let fingerprint = try FileFingerprint.read(url)
        let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .contentTypeKey, .tagNamesKey])
        var type = values.contentType ?? .data
        var width: Int?
        var height: Int?
        if type.conforms(to: .image), let image = CGImageSourceCreateWithURL(url as CFURL, nil) {
            if let actual = CGImageSourceGetType(image) as String?, let detected = UTType(actual) { type = detected }
            let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any]
            width = properties?[kCGImagePropertyPixelWidth as String] as? Int
            height = properties?[kCGImagePropertyPixelHeight as String] as? Int
            if let orientation = properties?[kCGImagePropertyOrientation as String] as? Int, orientation >= 5 {
                swap(&width, &height)
            }
        }
        let content = includeText ? readText(url, type: type, size: fingerprint.size) : (nil, nil)
        return Self(url: url, fingerprint: fingerprint, creationDate: values.creationDate,
            modificationDate: values.contentModificationDate, typeIdentifier: type.identifier,
            category: category(type), width: width, height: height, tags: values.tagNames ?? [],
            text: content.0, textIssue: content.1)
    }

    private static func category(_ type: UTType) -> String {
        if type.conforms(to: .pdf) { return "PDF" }
        if type.conforms(to: .image) { return "Image" }
        if type.conforms(to: .movie) { return "Video" }
        if type.conforms(to: .audio) { return "Audio" }
        if type.conforms(to: .archive) { return "Archive" }
        if type.conforms(to: .text) || type.conforms(to: .content) { return "Document" }
        return "Other"
    }

    private static func readText(_ url: URL, type: UTType, size: Int64) -> (String?, String?) {
        guard size <= 20_000_000 else { return (nil, "Text matching is limited to files up to 20 MB.") }
        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount <= 500 else {
                return (nil, "PDF text is unavailable, locked, or exceeds 500 pages.")
            }
            var result = ""
            for index in 0..<document.pageCount {
                if Task.isCancelled { return (nil, "Canceled") }
                result += (document.page(at: index)?.string ?? "") + "\n"
                if result.utf8.count > 2_000_000 { return (nil, "Document text exceeds 2 MB.") }
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (nil, "This PDF has no searchable text. OCR is not supported.") : (result, nil)
        }
        let plain = type.conforms(to: .plainText) || ["txt", "md", "csv", "json", "log", "yaml", "yml"].contains(url.pathExtension.lowercased())
        guard plain, size <= 2_000_000, let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            return (nil, "Text matching supports UTF-8 plain text up to 2 MB and searchable PDFs.")
        }
        return (text, nil)
    }
}

nonisolated enum AutomationConditionService {
    static func firstMatch(_ rules: [AutomationRule], facts: AutomationFileFacts, isSubfolder: Bool = false) throws -> AutomationRule? {
        for rule in rules where rule.isEnabled && (!isSubfolder || rule.includeSubfolders) {
            if try matches(rule, facts: facts) { return rule }
        }
        return nil
    }

    static func matches(_ rule: AutomationRule, facts: AutomationFileFacts) throws -> Bool {
        guard !rule.conditions.isEmpty else { return false }
        let matches = try rule.conditions.map { try matches($0, facts: facts) }
        return rule.matchAll ? matches.allSatisfy { $0 } : matches.contains(true)
    }

    static func matches(_ condition: AutomationCondition, facts: AutomationFileFacts) throws -> Bool {
        let field = condition.field
        if field.numeric || field.dated {
            let actual: Double?
            let expected: Double?
            switch field {
            case .size: actual = Double(facts.fingerprint.size) / 1_000_000; expected = Double(condition.value)
            case .width: actual = facts.width.map(Double.init); expected = Double(condition.value)
            case .height: actual = facts.height.map(Double.init); expected = Double(condition.value)
            case .created: actual = facts.creationDate.map { Calendar.current.startOfDay(for: $0).timeIntervalSince1970 }; expected = date(condition.value)?.timeIntervalSince1970
            default: actual = facts.modificationDate.map { Calendar.current.startOfDay(for: $0).timeIntervalSince1970 }; expected = date(condition.value)?.timeIntervalSince1970
            }
            guard let actual, let expected, actual.isFinite, expected.isFinite else { return false }
            switch condition.comparison {
            case .equals: return actual == expected
            case .notEquals: return actual != expected
            case .greater: return actual > expected
            case .less: return actual < expected
            default: return false
            }
        }
        let values: [String]
        switch field {
        case .name: values = [facts.url.lastPathComponent]
        case .fileExtension: values = [facts.url.pathExtension]
        case .category: values = [facts.category]
        case .tags: values = facts.tags
        case .text: guard let text = facts.text else { return false }; values = [text]
        case .typeIdentifier:
            guard let expected = UTType(condition.value), let actual = UTType(facts.typeIdentifier) else { return false }
            let conforms = actual.conforms(to: expected)
            return condition.comparison == .equals ? conforms : !conforms
        default: return false
        }
        let negative = [.notEquals, .notContains].contains(condition.comparison)
        let any = values.contains { value in
            let value = value.lowercased(), expected = condition.value.lowercased()
            switch condition.comparison {
            case .equals, .notEquals: return value == expected
            case .contains, .notContains: return value.contains(expected)
            case .startsWith: return value.hasPrefix(expected)
            case .endsWith: return value.hasSuffix(expected)
            default: return false
            }
        }
        return negative ? !any : any
    }

    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard value.count == 10, let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
}
