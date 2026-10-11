import AppKit
import SwiftUI

@MainActor final class ClipboardResultPanel {
    private let panel: NSPanel
    init(result: ClipboardOptimizationResult, copy: @escaping () -> Void, save: @escaping () -> Void,
         reveal: @escaping () -> Void, onClose: @escaping () -> Void) {
        let panel = ClipboardResultWindow(contentRect: NSRect(x: 0, y: 0, width: 330, height: 180),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        panel.contentView = NSHostingView(rootView: ClipboardResultCard(result: result,
            copy: copy, save: save, reveal: reveal, close: { [weak panel] in panel?.orderOut(nil); onClose() }))
    }
    func show() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: max(visible.minX, visible.maxX - 346), y: visible.minY + 16))
        panel.orderFrontRegardless()
    }
    func close() { panel.orderOut(nil) }
}

private struct ClipboardResultCard: View {
    let result: ClipboardOptimizationResult
    let copy: () -> Void
    let save: () -> Void
    let reveal: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let image = NSImage(data: result.thumbnailData) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                }
                Text("Clipboard Optimized").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.accessibilityLabel("Close clipboard result")
            }
            Text("\(size(result.originalBytes)) to \(size(Int64(result.data.count)))")
            if let percentage = result.percentage {
                Text("\(percentage.formatted(.number.precision(.fractionLength(0))))% smaller")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Copy", action: copy)
                Button("Save...", action: save)
                if result.fileBacked { Button("Reveal", action: reveal) }
                Spacer()
                Text("\(result.width) × \(result.height)").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).frame(width: 330, height: 180)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .onExitCommand(perform: close)
    }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

private final class ClipboardResultWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
