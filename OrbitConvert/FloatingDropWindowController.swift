import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FloatingDropWindowController {
    private var panel: NSPanel?
    private let onClose: () -> Void

    init(onDrop: @escaping ([NSItemProvider]) -> Bool, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let size = CGSize(width: 270, height: 180)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        let content = FloatingDropTargetView(onDrop: onDrop) { [weak self] in self?.dismiss() }
        panel.contentView = NSHostingView(rootView: content)
        self.panel = panel
    }

    @discardableResult
    func show() -> Bool {
        guard let panel else { return false }
        let screens = NSScreen.screens.map { FloatingScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        guard let frame = FloatingPanelPlacement.frame(near: NSEvent.mouseLocation,
                                                       size: panel.frame.size, screens: screens) else { return false }
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        return true
    }

    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
        onClose()
    }
}

private struct FloatingDropTargetView: View {
    let onDrop: ([NSItemProvider]) -> Bool
    let onClose: () -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close floating drop target")
            }
            Image(systemName: "square.and.arrow.down")
                .font(.title)
                .accessibilityHidden(true)
            Text("Drop files here")
                .font(.headline)
            Text("Then choose a conversion")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: onDrop)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating file drop target")
    }
}
