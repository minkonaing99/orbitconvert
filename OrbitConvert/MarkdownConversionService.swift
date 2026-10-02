import AppKit
import Foundation
import PDFKit

struct MarkdownConversionService: Sendable {
    nonisolated init() {}

    nonisolated static func validate(_ data: Data) throws -> String {
        guard data.count <= 10_000_000, !data.contains(0), let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentConversionError.invalidMarkdown
        }
        return text
    }

    nonisolated static func sanitize(_ data: Data, images: MarkdownImageResources? = nil) throws -> (data: Data, omittedImages: Int) {
        guard data.count <= 40_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["blocks"] as? [Any], let version = root["pandoc-api-version"] as? [Int] else {
            throw DocumentConversionError.invalidMarkdown
        }
        var omitted = 0
        var nodes = 0
        var imageCount = 0
        var imageBytes = 0
        var imagePixels = 0
        func clean(_ value: Any, depth: Int) throws -> Any {
            nodes += 1
            guard depth < 100, nodes < 500_000 else { throw DocumentConversionError.invalidMarkdown }
            if let array = value as? [Any] { return try array.map { try clean($0, depth: depth + 1) } }
            guard let object = value as? [String: Any] else { return value }
            let type = object["t"] as? String
            if type == "RawInline" { return ["t": "Str", "c": ""] }
            if type == "RawBlock" { return ["t": "Para", "c": []] }
            if type == "Image", let content = object["c"] as? [Any], content.count == 3 {
                imageCount += 1
                if imageCount <= 100, let target = content[2] as? [String], let href = target.first,
                   let resource = try images?.load(href, pixelBudget: 24_000_000 - imagePixels),
                   imageBytes + resource.dataURI.utf8.count <= 40_000_000 {
                    imageBytes += resource.dataURI.utf8.count
                    imagePixels += resource.pixels
                    return ["t": "Image", "c": [["", [], []],
                        try clean(content[1], depth: depth + 1), [resource.dataURI, ""]]]
                }
                omitted += 1
                return ["t": "Span", "c": [["", [], []], try clean(content[1], depth: depth + 1)]]
            }
            if type == "Link", let content = object["c"] as? [Any], content.count == 3,
               let target = content[2] as? [String], let href = target.first {
                let scheme = URL(string: href)?.scheme?.lowercased()
                if !href.hasPrefix("#") && !["https", "http", "mailto"].contains(scheme ?? "") {
                    return ["t": "Span", "c": [["", [], []], try clean(content[1], depth: depth + 1)]]
                }
            }
            // Drop user attributes so neither writer receives raw style or resource directives.
            if ["Code", "CodeBlock", "Span", "Div", "Header", "Link"].contains(type ?? ""),
               var content = object["c"] as? [Any] {
                let index = type == "Header" ? 1 : 0
                if content.indices.contains(index) { content[index] = ["", [], []] }
                return ["t": type ?? "", "c": try clean(content, depth: depth + 1)]
            }
            var copy: [String: Any] = [:]
            for (key, item) in object { copy[key] = try clean(item, depth: depth + 1) }
            return copy
        }
        let safe: [String: Any] = ["pandoc-api-version": version, "meta": [:], "blocks": try clean(blocks, depth: 0)]
        return (try JSONSerialization.data(withJSONObject: safe), omitted)
    }

    nonisolated func convert(_ file: FileItem, toDOCX: Bool, in directory: URL,
                             imageFolder: URL? = nil, pdfStyle: MarkdownPDFStyle = MarkdownPDFStyle()) async throws -> FileActionReport {
        guard file.isMarkdown else { throw DocumentConversionError.invalidMarkdown }
        let sourceScoped = file.url.startAccessingSecurityScopedResource()
        defer { if sourceScoped { file.url.stopAccessingSecurityScopedResource() } }
        let destinationScoped = directory.startAccessingSecurityScopedResource()
        defer { if destinationScoped { directory.stopAccessingSecurityScopedResource() } }
        let imagesScoped = imageFolder?.startAccessingSecurityScopedResource() ?? false
        defer { if imagesScoped { imageFolder?.stopAccessingSecurityScopedResource() } }
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        let size = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 10_000_000 else { throw DocumentConversionError.invalidMarkdown }
        let input = try Data(contentsOf: file.url)
        _ = try Self.validate(input)
        try input.write(to: job.appendingPathComponent("input.md"))
        let tool = BundledDocumentTool()
        try tool.run("pandoc", arguments: ["--sandbox", "--from=gfm-raw_html", "--to=json", "--output=parsed.json", "input.md"], in: job)
        let parsed = try boundedData(job.appendingPathComponent("parsed.json"), limit: 40_000_000)
        let resources = imageFolder.map { MarkdownImageResources(root: $0, sourceDirectory: file.url.deletingLastPathComponent()) }
        let safe = try Self.sanitize(parsed, images: resources)
        try safe.data.write(to: job.appendingPathComponent("safe.json"))
        let suffix = toDOCX ? "docx" : "pdf"
        let candidate = job.appendingPathComponent("output." + suffix)
        if toDOCX {
            try tool.run("pandoc", arguments: ["--sandbox", "--from=json", "--to=docx", "--output=output.docx", "safe.json"], in: job)
            _ = try boundedData(candidate, limit: 100_000_000)
            try tool.run("pandoc", arguments: ["--sandbox", "--from=docx", "--to=plain", "--output=verified.txt", "output.docx"], in: job)
            guard !String(decoding: try boundedData(job.appendingPathComponent("verified.txt"), limit: 40_000_000), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentConversionError.invalidOutput }
        } else {
            let illustrated = try Self.pdfImages(safe.data)
            try illustrated.data.write(to: job.appendingPathComponent("print.json"))
            try tool.run("pandoc", arguments: ["--sandbox", "--from=json", "--to=rtf", "--standalone", "--output=output.rtf", "print.json"], in: job)
            let rtf = try boundedData(job.appendingPathComponent("output.rtf"), limit: 40_000_000)
            try await MarkdownPDFRenderer.render(rtf, to: candidate, style: pdfStyle, images: illustrated.images)
            guard let document = PDFDocument(url: candidate), document.pageCount > 0 else { throw DocumentConversionError.invalidOutput }
        }
        try Task.checkCancellation()
        let output = FileOutputService()
        let temporary = try output.makeTemporaryFile(in: directory)
        defer { output.removeTemporaryFile(temporary) }
        try FileManager.default.copyItem(at: candidate, to: temporary)
        let url = try output.publish(temporary, stem: file.url.deletingPathExtension().lastPathComponent,
                                     fileExtension: suffix, in: directory)
        return FileActionReport(outputURLs: [url], message: "Saved \(url.lastPathComponent)" +
                                (safe.omittedImages > 0 ? ". \(safe.omittedImages) image(s) omitted; alt text retained." : ""), compression: nil)
    }

    nonisolated private static func pdfImages(_ data: Data) throws -> (data: Data, images: [String: Data]) {
        let root = try JSONSerialization.jsonObject(with: data)
        var images: [String: Data] = [:]
        func replace(_ value: Any) throws -> Any {
            if let array = value as? [Any] { return try array.map(replace) }
            guard let object = value as? [String: Any] else { return value }
            if object["t"] as? String == "Image", let content = object["c"] as? [Any],
               content.count == 3, let target = content[2] as? [String], let href = target.first,
               href.hasPrefix("data:image/png;base64,"),
               let bytes = Data(base64Encoded: String(href.dropFirst("data:image/png;base64,".count))) {
                let marker = "OrbitConvertImage" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                images[marker] = bytes
                return ["t": "Str", "c": marker]
            }
            return try object.mapValues(replace)
        }
        return (try JSONSerialization.data(withJSONObject: replace(root)), images)
    }

    nonisolated private func boundedData(_ url: URL, limit: Int) throws -> Data {
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 0, bytes <= limit else { throw DocumentConversionError.invalidOutput }
        return try Data(contentsOf: url)
    }
}
