import Foundation

// Finds math and Mermaid code blocks in sanitized Pandoc JSON and swaps rendered ones for text markers that
// MarkdownPDFRenderer later replaces with vector attachments. Unrendered items stay as they are.
nonisolated enum MarkdownGraphics {
    static func collect(_ json: Data) throws -> [MarkdownGraphic] {
        var found: [MarkdownGraphic] = []
        func visit(_ value: Any) {
            if let array = value as? [Any] { array.forEach(visit); return }
            guard let object = value as? [String: Any] else { return }
            if let graphic = graphic(in: object) { found.append(graphic) }
            object.values.forEach(visit)
        }
        visit(try JSONSerialization.jsonObject(with: json))
        return found
    }

    static func replace(_ json: Data, rendered: [MarkdownGraphic: RenderedGraphic]) throws
        -> (data: Data, graphics: [String: RenderedGraphic]) {
        var markers: [String: RenderedGraphic] = [:]
        func swap(_ value: Any) -> Any {
            if let array = value as? [Any] { return array.map(swap) }
            guard let object = value as? [String: Any] else { return value }
            if let graphic = graphic(in: object), let result = rendered[graphic] {
                let marker = "OrbitConvertGraphic" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                markers[marker] = result
                let text: [String: Any] = ["t": "Str", "c": marker]
                return graphic.kind == .mermaid ? ["t": "Para", "c": [text]] : text
            }
            return object.mapValues(swap)
        }
        let swapped = swap(try JSONSerialization.jsonObject(with: json))
        return (try JSONSerialization.data(withJSONObject: swapped), markers)
    }

    private static func graphic(in object: [String: Any]) -> MarkdownGraphic? {
        guard let content = object["c"] as? [Any], content.count == 2 else { return nil }
        switch object["t"] as? String {
        case "Math":
            guard let mode = (content[0] as? [String: Any])?["t"] as? String, let source = content[1] as? String
            else { return nil }
            return MarkdownGraphic(kind: mode == "DisplayMath" ? .displayMath : .inlineMath, source: source)
        case "CodeBlock":
            guard let attributes = content[0] as? [Any], attributes.count == 3,
                  (attributes[1] as? [String])?.contains("mermaid") == true, let source = content[1] as? String
            else { return nil }
            return MarkdownGraphic(kind: .mermaid, source: source)
        default:
            return nil
        }
    }
}
