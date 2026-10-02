import AppKit
import Foundation

nonisolated struct MarkdownPDFStyle: Sendable {
    var bodySize = 12.0
    var margin = 40.0
    var useLetter = false
    var useSerif = false

    func validate() throws {
        guard bodySize.isFinite, (8...24).contains(bodySize), margin.isFinite,
              (20...90).contains(margin) else { throw DocumentConversionError.invalidOutput }
    }
}

@MainActor
final class MarkdownPDFRenderer: NSObject {
    private var continuation: CheckedContinuation<Void, Error>?
    private var deadline: Task<Void, Never>?
    private var operation: NSPrintOperation?
    private var window: NSWindow?
    private var cancellationRequested = false
    private var timeoutRequested = false

    static func render(_ rtf: Data, to destination: URL, style: MarkdownPDFStyle = MarkdownPDFStyle(),
                       images: [String: Data] = [:]) async throws {
        try style.validate()
        let renderer = MarkdownPDFRenderer()
        let imported = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                              documentAttributes: nil)
        let document = try attachImages(imported, images: images, style: style)
        guard document.length > 0 else { throw DocumentConversionError.invalidOutput }
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                renderer.continuation = continuation
                renderer.deadline = Task {
                    try? await Task.sleep(for: .seconds(60))
                    if !Task.isCancelled { renderer.timeoutRequested = true }
                }
                renderer.printDocument(styled(document, style: style), to: destination, style: style)
            }
        } onCancel: {
            Task { @MainActor in renderer.cancellationRequested = true }
        }
    }

    private static func attachImages(_ document: NSAttributedString, images: [String: Data],
                                     style: MarkdownPDFStyle) throws -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: document)
        let width = (style.useLetter ? 612.0 : 595.28) - 2 * style.margin
        let height = (style.useLetter ? 792.0 : 841.89) - 2 * style.margin
        for (marker, data) in images {
            try Task.checkCancellation()
            let range = (copy.string as NSString).range(of: marker)
            guard range.location != NSNotFound, let image = NSImage(data: data),
                  image.size.width > 0, image.size.height > 0 else { throw DocumentConversionError.invalidOutput }
            let scale = min(1, width / image.size.width, (height - 40) / image.size.height)
            image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let attachment = NSTextAttachment()
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
            copy.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
        }
        return NSAttributedString(attributedString: copy)
    }

    private static func styled(_ document: NSAttributedString, style: MarkdownPDFStyle) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: document)
        document.enumerateAttribute(.font, in: NSRange(location: 0, length: document.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let family = font.isFixedPitch ? font : NSFontManager.shared.convert(font, toFamily: style.useSerif ? "Georgia" : "Helvetica")
            copy.addAttribute(.font, value: NSFontManager.shared.convert(family, toSize: font.pointSize * style.bodySize / 12), range: range)
        }
        return NSAttributedString(attributedString: copy)
    }

    private func printDocument(_ document: NSAttributedString, to destination: URL, style: MarkdownPDFStyle) {
        let info = NSPrintInfo()
        info.paperSize = style.useLetter ? NSSize(width: 612, height: 792) : NSSize(width: 595.28, height: 841.89)
        info.topMargin = style.margin
        info.bottomMargin = style.margin
        info.leftMargin = style.margin
        info.rightMargin = style.margin
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        textView.isRichText = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(document)
        guard let container = textView.textContainer, let layout = textView.layoutManager else {
            finish(DocumentConversionError.invalidOutput)
            return
        }
        // AppKit layout handles NSTextTableBlock; Core Text alone flattens table cells.
        layout.ensureLayout(for: container)
        let height = ceil(layout.usedRect(for: container).height)
        guard height > 0, height <= 1_000_000 else {
            finish(DocumentConversionError.invalidOutput)
            return
        }
        textView.setFrameSize(NSSize(width: width, height: height))
        let printOperation = NSPrintOperation(view: textView, printInfo: info)
        printOperation.showsPrintPanel = false
        printOperation.showsProgressPanel = false
        operation = printOperation
        let parent = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window = parent
        printOperation.runModal(for: parent, delegate: self,
            didRun: #selector(printFinished(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printFinished(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        // Let native printing finish before releasing its delegate or removing job files.
        if cancellationRequested { finish(CancellationError()) }
        else if timeoutRequested { finish(DocumentConversionError.timedOut) }
        else { finish(success ? nil : DocumentConversionError.invalidOutput) }
    }

    private func finish(_ error: Error?) {
        guard let pending = continuation else { return }
        continuation = nil
        deadline?.cancel()
        operation = nil
        window?.orderOut(nil)
        window = nil
        if let error { pending.resume(throwing: error) } else { pending.resume() }
    }
}
