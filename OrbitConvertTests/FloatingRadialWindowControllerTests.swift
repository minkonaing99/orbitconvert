import AppKit
import XCTest
@testable import OrbitConvert

final class FloatingRadialWindowControllerTests: XCTestCase {
    @MainActor
    func testPanelOpensWithoutTitleBarAndDismisses() throws {
        let file = FileItem(
            url: URL(fileURLWithPath: "/tmp/sample.png"), fileName: "sample.png", fileExtension: "png",
            contentTypeIdentifier: "public.png", contentTypeName: "PNG image", fileSize: 100,
            creationDate: nil, pixelWidth: 10, pixelHeight: 10, pageCount: nil, thumbnailData: Data(),
            supportedConversions: [.jpeg]
        )
        var didClose = false
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = FloatingRadialWindowController(
            file: file, actions: [FileAction(format: .jpeg)],
            onSelect: { _ in XCTFail("The test did not select an action") },
            onClose: { didClose = true }
        )

        XCTAssertTrue(controller.show())
        let panel = try XCTUnwrap(NSApp.windows.first { !existing.contains(ObjectIdentifier($0)) } as? NSPanel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isOpaque)

        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
        ))
        NSApp.sendEvent(escape)
        XCTAssertTrue(didClose)
        XCTAssertTrue(panel.ignoresMouseEvents)
    }

    @MainActor
    func testTransparentCornerClickDismisses() throws {
        let file = FileItem(
            url: URL(fileURLWithPath: "/tmp/sample.png"), fileName: "sample.png", fileExtension: "png",
            contentTypeIdentifier: "public.png", contentTypeName: "PNG image", fileSize: 100,
            creationDate: nil, pixelWidth: 10, pixelHeight: 10, pageCount: nil, thumbnailData: Data(),
            supportedConversions: [.jpeg]
        )
        var didClose = false
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = FloatingRadialWindowController(
            file: file, actions: [FileAction(format: .jpeg)], onSelect: { _ in XCTFail() },
            onClose: { didClose = true }
        )
        XCTAssertTrue(controller.show())
        let panel = try XCTUnwrap(NSApp.windows.first { !existing.contains(ObjectIdentifier($0)) } as? NSPanel)
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: CGPoint(x: 1, y: 1), modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))

        NSApp.sendEvent(click)

        XCTAssertTrue(didClose)
    }
}
