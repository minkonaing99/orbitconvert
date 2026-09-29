import AppKit
import SwiftUI

@MainActor
final class FloatingActionPanelController {
    private static weak var active: FloatingActionPanelController?
    private var panel: FloatingActionPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?
    private let onClose: () -> Void
    private let onSelect: (FileAction) -> Void
    private let actions: [FileAction]
    private var focusedAction: FileAction?

    init(file: FileItem, actions: [FileAction], onSelect: @escaping (FileAction) -> Void,
         onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.onSelect = onSelect
        self.actions = actions
        self.focusedAction = actions.first { $0.category == .conversion } ?? actions.first
        let conversionCount = actions.filter { $0.category == .conversion }.count
        let toolCount = actions.count - conversionCount
        let rows = (conversionCount + 2) / 3 + (toolCount + 2) / 3
        let sections = (conversionCount > 0 ? 1 : 0) + (toolCount > 0 ? 1 : 0)
        let size = CGSize(width: 390, height: CGFloat(min(560, 105 + rows * 44 + sections * 40)))
        let panel = FloatingActionPanel(contentRect: CGRect(origin: .zero, size: size),
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
        let content = FileActionPanelView(file: file, actions: actions, isEnabled: true,
                                          returnSelectsFirstAction: true) { [weak self] action in
            guard let self, self.panel != nil else { return }
            self.dismiss()
            self.onSelect(action)
        } onDismiss: { [weak self] in
            self?.dismiss()
        } onFocusChanged: { [weak self] id in
            self?.focusedAction = actions.first { $0.id == id }
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
        return FloatingPanelPlacement.frame(near: NSEvent.mouseLocation, size: size, screens: screens)
    }

    private func reposition() {
        guard let panel, let frame = placementFrame(for: panel.frame.size) else { dismiss(); return }
        panel.setFrame(frame, display: true)
    }

    private func installObservers() {
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [mouse, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown, event.window === panel {
                if event.keyCode == 53 {
                    self.dismiss()
                    return nil
                }
                if (event.keyCode == 36 || event.keyCode == 76), let action = self.focusedAction {
                    self.dismiss()
                    self.onSelect(action)
                    return nil
                }
            }
            if (event.type == .leftMouseDown || event.type == .rightMouseDown), event.window !== panel {
                self.dismiss()
            } else if event.type == .leftMouseDown || event.type == .rightMouseDown {
                let shape = NSBezierPath(roundedRect: panel.contentView?.bounds ?? .zero,
                                         xRadius: 16, yRadius: 16)
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

private final class FloatingActionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
