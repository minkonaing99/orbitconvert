import AppKit
import XCTest
@testable import OrbitConvert

final class FloatingDropWindowControllerTests: XCTestCase {
    @MainActor
    func testPanelStaysAvailableWithoutActivatingApp() throws {
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        var didClose = false
        let controller = FloatingDropWindowController(onDrop: { _ in true }, onClose: { didClose = true })

        XCTAssertTrue(controller.show())
        let panel = try XCTUnwrap(NSApp.windows.first { !existing.contains(ObjectIdentifier($0)) } as? NSPanel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertFalse(panel.hidesOnDeactivate)

        controller.dismiss()
        XCTAssertTrue(didClose)
        XCTAssertFalse(panel.isVisible)
    }
}
