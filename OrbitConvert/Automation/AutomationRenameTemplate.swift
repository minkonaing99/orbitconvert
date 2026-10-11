import Foundation

nonisolated struct AutomationRenameTemplate: Sendable {
    private enum Part: Sendable { case literal(String), date(String), name, ext, increment(Int) }
    private let parts: [Part]
    var usesIncrement: Bool { parts.contains { if case .increment = $0 { true } else { false } } }
    var usesDate: Bool { parts.contains { if case .date = $0 { true } else { false } } }

    init(_ pattern: String) throws {
        guard !pattern.isEmpty, pattern.utf8.count <= 1_024 else { throw AutomationError.invalid("Enter a rename pattern up to 1,024 bytes.") }
        var rest = pattern[...]
        var result: [Part] = []
        while !rest.isEmpty {
            if rest.hasPrefix("''") { result.append(.literal("'")); rest = rest.dropFirst(2); continue }
            if rest.first == "'" {
                rest = rest.dropFirst()
                var literal = ""
                var closed = false
                while let character = rest.first {
                    rest = rest.dropFirst()
                    if character == "'" {
                        if rest.first == "'" { literal += "'"; rest = rest.dropFirst(); continue }
                        closed = true; break
                    }
                    literal.append(character)
                }
                guard closed else { throw AutomationError.invalid("Close the quoted text in the rename pattern.") }
                result.append(.literal(literal)); continue
            }
            if rest.first == "{" {
                guard let end = rest.firstIndex(of: "}") else { throw AutomationError.invalid("Close each rename token with }.") }
                let token = String(rest[rest.index(after: rest.startIndex)..<end])
                result.append(try Self.token(token))
                rest = rest[rest.index(after: end)...]; continue
            }
            if rest.first == "}" { throw AutomationError.invalid("Unexpected } in the rename pattern.") }
            if let token = ["yyyy", "yy", "MM", "dd", "HH", "mm", "ss"].first(where: { rest.hasPrefix($0) }) {
                result.append(.date(token)); rest = rest.dropFirst(token.count)
            } else {
                result.append(.literal(String(rest.removeFirst())))
            }
        }
        parts = result
        _ = try render(originalName: "Example", fileExtension: "png", creationDate: Date(), modificationDate: nil, index: 1)
    }

    private static func token(_ token: String) throws -> Part {
        switch token {
        case "name": return .name
        case "ext": return .ext
        case "i": return .increment(1)
        default:
            if token.hasPrefix("i:0"), let width = Int(token.dropFirst(3)), (1...9).contains(width) {
                return .increment(width)
            }
            throw AutomationError.invalid("Unknown rename token {\(token)}. Use name, ext, i, or i:03.")
        }
    }

    func render(originalName: String, fileExtension: String, creationDate: Date?, modificationDate: Date?,
                index: Int, timeZone: TimeZone = .current) throws -> String {
        guard index >= 1 else { throw AutomationError.invalid("Filename numbering starts at 1.") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = creationDate ?? modificationDate
        if usesDate && date == nil { throw AutomationError.invalid("This file has no creation or modification date for renaming.") }
        let fields = date.map { calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0) }
        var name = ""
        var explicitExtension = false
        for part in parts {
            switch part {
            case .literal(let value): name += value
            case .name: name += originalName
            case .ext: name += fileExtension; explicitExtension = true
            case .increment(let width): name += String(format: "%0*lld", width, Int64(index))
            case .date(let token):
                let value: Int
                switch token {
                case "yyyy": value = fields?.year ?? 0
                case "yy": value = (fields?.year ?? 0) % 100
                case "MM": value = fields?.month ?? 0
                case "dd": value = fields?.day ?? 0
                case "HH": value = fields?.hour ?? 0
                case "mm": value = fields?.minute ?? 0
                default: value = fields?.second ?? 0
                }
                name += String(format: token == "yyyy" ? "%04d" : "%02d", value)
            }
        }
        if explicitExtension, fileExtension.isEmpty, name.hasSuffix(".") { name.removeLast() }
        if !explicitExtension, !fileExtension.isEmpty, !name.lowercased().hasSuffix("." + fileExtension.lowercased()) {
            name += "." + fileExtension
        }
        if explicitExtension && !fileExtension.isEmpty && !name.lowercased().hasSuffix("." + fileExtension.lowercased()) {
            throw AutomationError.invalid("Place .{ext} at the end to preserve the file format.")
        }
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("."), name.utf8.count <= 255,
              !name.contains("/"), !name.contains(":"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AutomationError.invalid("Use a visible filename under 256 bytes without slashes, colons, or control characters.")
        }
        return name
    }
}
