import AppKit
import SwiftUI

@MainActor final class ClipboardResultPanel {
    private let panel: NSPanel
    private let onClose: () -> Void
    private let autoDismiss: Duration
    private var dismissal: Task<Void, Never>?

    /// The card closes itself after `autoDismiss`, but waits while the pointer is over it.
    init(result: ClipboardOptimizationResult, copy: @escaping () -> Void, save: @escaping () -> Void,
         reveal: @escaping () -> Void, onClose: @escaping () -> Void, autoDismiss: Duration = .seconds(6)) {
        let panel = ClipboardResultWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        self.onClose = onClose
        self.autoDismiss = autoDismiss
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        let host = NSHostingView(rootView: ClipboardResultCard(result: result, copy: copy, save: save, reveal: reveal,
                                                                close: { [weak self] in self?.dismiss() }))
        host.setFrameSize(host.fittingSize)
        panel.setContentSize(host.fittingSize)
        panel.contentView = host
    }

    func show() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: max(visible.minX, visible.maxX - panel.frame.width - 16), y: visible.minY + 16))
        panel.orderFrontRegardless()
        scheduleDismissal()
    }

    func close() {
        dismissal?.cancel()
        panel.orderOut(nil)
    }

    private func dismiss() {
        close()
        onClose()
    }

    private func scheduleDismissal() {
        dismissal?.cancel()
        dismissal = Task { [weak self, autoDismiss] in
            try? await Task.sleep(for: autoDismiss)
            guard !Task.isCancelled, let self else { return }
            if self.panel.frame.contains(NSEvent.mouseLocation) { self.scheduleDismissal() } else { self.dismiss() }
        }
    }
}

private struct ClipboardResultCard: View {
    let result: ClipboardOptimizationResult
    let copy: () -> Void
    let save: () -> Void
    let reveal: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved \(size(result.savedBytes))").font(.headline)
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(result.width) × \(result.height) px").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 20, height: 20).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close clipboard result")
            }
            HStack(spacing: 8) {
                Button("Copy", action: copy).help("Copy the optimized image again")
                Button("Save...", action: save)
                if result.fileBacked { Button("Show in Finder", action: reveal) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard optimized")
        .onExitCommand(perform: close)
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = NSImage(data: result.thumbnailData) {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .accessibilityHidden(true)
        }
    }

    private var summary: String {
        let change = "\(size(result.originalBytes)) to \(size(Int64(result.data.count)))"
        guard let percentage = result.percentage else { return change }
        return "\(percentage.formatted(.number.precision(.fractionLength(0))))% smaller, \(change)"
    }

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

private final class ClipboardResultWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
