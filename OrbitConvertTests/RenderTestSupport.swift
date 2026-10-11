import AppKit
import SwiftUI
import XCTest

extension XCTestCase {
    @MainActor
    // Width is fixed to the window so text wraps as it would on screen; height must fit unless the content scrolls.
    func render<V: View>(_ root: V, width: CGFloat, height: CGFloat, dark: Bool,
                         settle: TimeInterval = 0.2, scrolls: Bool = false) throws {
        if !scrolls {
            let wrapped = NSHostingView(rootView: root.frame(width: width)).fittingSize
            XCTAssertLessThanOrEqual(wrapped.height, height, "Content is taller than its window")
        }
        let view = NSHostingView(rootView: root.frame(width: width, height: height))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertFalse(isUniform(bitmap), "Rendered view is blank")
    }

    private func isUniform(_ bitmap: NSBitmapImageRep) -> Bool {
        guard let first = bitmap.colorAt(x: 0, y: 0) else { return true }
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 7) where bitmap.colorAt(x: x, y: y) != first {
                return false
            }
        }
        return true
    }
}
