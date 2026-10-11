import Foundation
import PDFKit

// pdfwrite may drop links. Copy supported navigation onto the optimized pages,
// then compare a bounded semantic snapshot after saving and reopening the PDF.
struct PDFNavigationService {
    nonisolated static func snapshot(_ document: PDFDocument) throws -> [String] {
        var entries: [String] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index), page.annotations.count <= 5_000 else {
                throw DocumentConversionError.protectedPDF
            }
            for annotation in page.annotations {
                guard annotation.type == "Link", annotation.action is PDFActionURL, entries.count < 10_000 else {
                    throw DocumentConversionError.protectedPDF
                }
                let bounds = annotation.bounds
                let action = try actionKey(annotation.action, destination: annotation.destination, in: document)
                entries.append("link:\(index):\(number(bounds.origin.x)):\(number(bounds.origin.y)):\(number(bounds.width)):\(number(bounds.height)):\(action)")
                entries.append("contents:" + (annotation.contents ?? ""))
            }
        }
        var visited: Set<ObjectIdentifier> = []
        func outline(_ node: PDFOutline, depth: Int) throws {
            try Task.checkCancellation()
            guard depth < 32, entries.count < 10_000, visited.insert(ObjectIdentifier(node)).inserted,
                  node.numberOfChildren <= 5_000 else { throw DocumentConversionError.protectedPDF }
            entries.append("outline:\(depth):\(node.numberOfChildren):" + (node.label ?? ""))
            entries.append(try actionKey(node.action, destination: node.destination, in: document))
            for index in 0..<node.numberOfChildren {
                guard let child = node.child(at: index) else { throw DocumentConversionError.protectedPDF }
                try outline(child, depth: depth + 1)
            }
        }
        if let root = document.outlineRoot { try outline(root, depth: 0) }
        return entries
    }

    nonisolated static func restore(from source: PDFDocument, to candidate: PDFDocument) throws {
        _ = try snapshot(source)
        guard source.pageCount == candidate.pageCount else { throw DocumentConversionError.invalidOutput }
        for index in 0..<source.pageCount {
            try Task.checkCancellation()
            guard let before = source.page(at: index), let after = candidate.page(at: index) else {
                throw DocumentConversionError.invalidOutput
            }
            for annotation in after.annotations { after.removeAnnotation(annotation) }
            for annotation in before.annotations {
                guard let copy = annotation.copy() as? PDFAnnotation else { throw DocumentConversionError.invalidOutput }
                copy.destination = nil
                copy.action = try remap(annotation.action, destination: annotation.destination, source: source, candidate: candidate)
                after.addAnnotation(copy)
            }
        }
        // Keep pdfwrite's existing outline tree; reject output if its semantic snapshot differs.
    }

    nonisolated private static func actionKey(_ action: PDFAction?, destination: PDFDestination?,
                                              in document: PDFDocument) throws -> String {
        if let link = action as? PDFActionURL {
            guard let url = link.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else {
                throw DocumentConversionError.protectedPDF
            }
            return "url:" + url.absoluteString
        }
        guard action == nil || action is PDFActionGoTo else { throw DocumentConversionError.protectedPDF }
        if let target = (action as? PDFActionGoTo)?.destination ?? destination,
           let page = target.page, document.index(for: page) != NSNotFound {
            return "page:\(document.index(for: page)):\(number(target.point.x)):\(number(target.point.y)):\(number(target.zoom))"
        }
        guard action == nil, destination == nil else { throw DocumentConversionError.protectedPDF }
        return "none"
    }

    nonisolated private static func remap(_ action: PDFAction?, destination: PDFDestination?,
                                          source: PDFDocument, candidate: PDFDocument) throws -> PDFAction? {
        _ = try actionKey(action, destination: destination, in: source)
        if let link = action as? PDFActionURL, let url = link.url { return PDFActionURL(url: url) }
        guard let target = (action as? PDFActionGoTo)?.destination ?? destination else { return nil }
        guard let page = target.page, let outputPage = candidate.page(at: source.index(for: page)) else {
            throw DocumentConversionError.invalidOutput
        }
        let mapped = PDFDestination(page: outputPage, at: target.point)
        mapped.zoom = target.zoom
        return PDFActionGoTo(destination: mapped)
    }

    nonisolated private static func number(_ value: CGFloat) -> String {
        // PDF numeric serialization can round geometry; compare to a thousandth of a point.
        value.isFinite ? String((value * 1_000).rounded() / 1_000) : String(describing: value)
    }
}
