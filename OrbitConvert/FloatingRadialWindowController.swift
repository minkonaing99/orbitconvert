import AppKit
import SwiftUI

@MainActor
final class FloatingRadialWindowController {
    private static weak var active: FloatingRadialWindowController?
    private var panel: FloatingRadialPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?
    private let onClose: () -> Void

    init(file: FileItem, actions: [FileAction], onSelect: @escaping (FileAction) -> Void,
         onClose: @escaping () -> Void) {
        self.onClose = onClose
        let size = CGSize(width: 390, height: 430)
        let panel = FloatingRadialPanel(contentRect: CGRect(origin: .zero, size: size),
                                        styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        panel.isReleasedWhenClosed = false
        let content = RadialMenuView(file: file, actions: actions) { [weak self] action in
            guard let self, self.panel != nil else { return }
            self.dismiss()
            onSelect(action)
        } onDismiss: { [weak self] in
            self?.dismiss()
        }
        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
    }

    @discardableResult
    func show() -> Bool {
        Self.active?.dismiss()
        Self.active = self
        guard let panel, let frame = placementFrame(for: panel.frame.size) else {
            dismiss()
            return false
        }
        panel.setFrame(frame, display: false)
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reducedMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        if !reducedMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 1
            }
        }
        installObservers()
        return true
    }

    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        panel.ignoresMouseEvents = true
        if Self.active === self { Self.active = nil }
        removeObservers()
        onClose()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }

    private func placementFrame(for size: CGSize) -> CGRect? {
        let screens = NSScreen.screens.map { FloatingScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        return FloatingRadialPlacement.frame(near: NSEvent.mouseLocation, size: size, screens: screens)
    }

    private func reposition() {
        guard let panel, let frame = placementFrame(for: panel.frame.size) else { dismiss(); return }
        panel.setFrame(frame, display: true)
    }

    private func installObservers() {
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [mouse, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown, event.window === panel, event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            if (event.type == .leftMouseDown || event.type == .rightMouseDown), event.window !== panel {
                self.dismiss()
            } else if event.type == .leftMouseDown || event.type == .rightMouseDown {
                let shape = NSBezierPath(roundedRect: panel.contentView?.bounds ?? .zero,
                                         xRadius: 24, yRadius: 24)
                if !shape.contains(event.locationInWindow) {
                    self.dismiss()
                    return nil
                }
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouse) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismiss() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reposition() }
        }
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismiss() }
        }
    }

    private func removeObservers() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver); self.screenObserver = nil }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver); self.deactivateObserver = nil }
    }
}

private final class FloatingRadialPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
