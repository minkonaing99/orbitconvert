import CoreGraphics
import Foundation
import PDFKit

struct PDFOptimizationValidation {
    nonisolated static func inspect(_ url: URL, stronger: Bool) throws {
        guard let pdf = CGPDFDocument(url as CFURL), !pdf.isEncrypted,
              pdf.numberOfPages > 0, pdf.numberOfPages <= 2_000,
              let catalog = pdf.catalog else { throw DocumentConversionError.protectedPDF }
        var form: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form {
            if stronger { throw DocumentConversionError.protectedPDF }
            var fields: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(form, "Fields", &fields), let fields {
                var budget = 10_000
                try inspectFields(fields, depth: 0, budget: &budget)
            }
        }
        if exists(catalog, "Perms") { throw DocumentConversionError.protectedPDF }
        guard stronger else { return }
        for key in ["Names", "Dests", "OCProperties", "StructTreeRoot", "MarkInfo", "OutputIntents", "AA", "OpenAction", "Collection"] {
            if exists(catalog, key) { throw DocumentConversionError.protectedPDF }
        }
        for index in 1...pdf.numberOfPages {
            guard let page = pdf.page(at: index), let dictionary = page.dictionary else {
                throw DocumentConversionError.invalidOutput
            }
            if exists(dictionary, "AA") {
                throw DocumentConversionError.protectedPDF
            }
            var annotations: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(dictionary, "Annots", &annotations), let annotations {
                guard CGPDFArrayGetCount(annotations) <= 5_000 else { throw DocumentConversionError.protectedPDF }
                for index in 0..<CGPDFArrayGetCount(annotations) {
                    var annotation: CGPDFDictionaryRef?
                    var type: UnsafePointer<CChar>?
                    guard CGPDFArrayGetDictionary(annotations, index, &annotation), let annotation,
                          CGPDFDictionaryGetName(annotation, "Subtype", &type), let type,
                          String(cString: type) == "Link", !exists(annotation, "AA") else {
                        throw DocumentConversionError.protectedPDF
                    }
                    try inspectAction(annotation)
                }
            }
        }
        var outlines: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "Outlines", &outlines), let outlines {
            var budget = 5_000
            try inspectOutlineActions(outlines, depth: 0, budget: &budget)
        }
        guard let document = PDFDocument(url: url) else { throw DocumentConversionError.protectedPDF }
        _ = try PDFNavigationService.snapshot(document)
    }

    nonisolated private static func inspectAction(_ dictionary: CGPDFDictionaryRef) throws {
        guard exists(dictionary, "A") else { return }
        var action: CGPDFDictionaryRef?
        var type: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetDictionary(dictionary, "A", &action), let action,
              !exists(action, "Next"), CGPDFDictionaryGetName(action, "S", &type), let type,
              ["URI", "GoTo"].contains(String(cString: type)) else { throw DocumentConversionError.protectedPDF }
    }

    nonisolated private static func inspectOutlineActions(_ dictionary: CGPDFDictionaryRef, depth: Int,
                                                        budget: inout Int) throws {
        guard depth < 32 else { throw DocumentConversionError.protectedPDF }
        var current: CGPDFDictionaryRef? = dictionary
        while let node = current {
            try Task.checkCancellation()
            budget -= 1
            guard budget >= 0, !exists(node, "AA") else { throw DocumentConversionError.protectedPDF }
            try inspectAction(node)
            var child: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(node, "First", &child), let child {
                try inspectOutlineActions(child, depth: depth + 1, budget: &budget)
            }
            var next: CGPDFDictionaryRef?
            _ = CGPDFDictionaryGetDictionary(node, "Next", &next)
            current = next
        }
    }

    nonisolated private static func exists(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Bool {
        var object: CGPDFObjectRef?
        return CGPDFDictionaryGetObject(dictionary, key, &object)
    }

    nonisolated private static func inspectFields(_ fields: CGPDFArrayRef, depth: Int, budget: inout Int) throws {
        guard depth < 20, CGPDFArrayGetCount(fields) < 10_000 else { throw DocumentConversionError.protectedPDF }
        for index in 0..<CGPDFArrayGetCount(fields) {
            try Task.checkCancellation()
            budget -= 1
            guard budget >= 0 else { throw DocumentConversionError.protectedPDF }
            var field: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(fields, index, &field), let field else {
                throw DocumentConversionError.protectedPDF
            }
            var type: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(field, "FT", &type), let type, String(cString: type) == "Sig" {
                throw DocumentConversionError.protectedPDF
            }
            var children: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(field, "Kids", &children), let children {
                try inspectFields(children, depth: depth + 1, budget: &budget)
            }
        }
    }
}
