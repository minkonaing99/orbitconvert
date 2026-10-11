import AppKit
import SwiftUI
import XCTest
@testable import OrbitConvert

final class AutomationEditorTests: XCTestCase {
    @MainActor func testRuleEditorFitsAndDoesNotSaveOnOpen() {
        var saved = false
        let view = NSHostingView(rootView: AutomationRuleEditor(rule: AutomationRule(),
            onSave: { _ in saved = true }, onTest: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(view.fittingSize.width, 760)
        XCTAssertLessThanOrEqual(view.fittingSize.height, 620)
        XCTAssertFalse(saved)
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                attachment.name = "Automation Rule Editor"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
