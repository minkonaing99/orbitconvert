import CoreGraphics
import XCTest
@testable import OrbitConvert

final class FloatingPanelPlacementTests: XCTestCase {
    private let size = CGSize(width: 390, height: 430)

    func testCentersOnPointerWhenThereIsRoom() throws {
        let screen = FloatingScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
        let frame = try XCTUnwrap(FloatingPanelPlacement.frame(near: CGPoint(x: 720, y: 450), size: size,
                                                                 screens: [screen]))
        XCTAssertEqual(frame.origin.x, 525)
        XCTAssertEqual(frame.origin.y, 235)
        XCTAssertEqual(frame.size, size)
    }

    func testClampsAllEdgesToVisibleFrame() throws {
        let screen = FloatingScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                    visibleFrame: CGRect(x: 0, y: 40, width: 1000, height: 735))
        let lower = try XCTUnwrap(FloatingPanelPlacement.frame(near: CGPoint(x: 2, y: 2), size: size,
                                                                 screens: [screen]))
        let upper = try XCTUnwrap(FloatingPanelPlacement.frame(near: CGPoint(x: 998, y: 798), size: size,
                                                                 screens: [screen]))
        XCTAssertEqual(lower.origin, CGPoint(x: 0, y: 40))
        XCTAssertEqual(upper.origin, CGPoint(x: 610, y: 345))
    }

    func testChoosesNegativeOriginMonitorAndItsVisibleFrame() throws {
        let primary = FloatingScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
        let left = FloatingScreen(frame: CGRect(x: -1280, y: -100, width: 1280, height: 800),
                                  visibleFrame: CGRect(x: -1280, y: -100, width: 1280, height: 775))
        let frame = try XCTUnwrap(FloatingPanelPlacement.frame(near: CGPoint(x: -1260, y: 680), size: size,
                                                                 screens: [primary, left]))
        XCTAssertEqual(frame.origin, CGPoint(x: -1280, y: 245))
    }

    func testEmptyAndSmallScreens() throws {
        XCTAssertNil(FloatingPanelPlacement.frame(near: .zero, size: size, screens: []))
        let small = FloatingScreen(frame: CGRect(x: 0, y: 0, width: 300, height: 300),
                                   visibleFrame: CGRect(x: 0, y: 0, width: 280, height: 260))
        XCTAssertNil(FloatingPanelPlacement.frame(near: CGPoint(x: 150, y: 150), size: size,
                                                  screens: [small]))
    }

    func testPointerOutsideScreensUsesNearestDisplay() throws {
        let left = FloatingScreen(frame: CGRect(x: -1200, y: 0, width: 1000, height: 800),
                                  visibleFrame: CGRect(x: -1200, y: 0, width: 1000, height: 775))
        let primary = FloatingScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 775))
        let frame = try XCTUnwrap(FloatingPanelPlacement.frame(near: CGPoint(x: -50, y: 400), size: size,
                                                                 screens: [left, primary]))
        XCTAssertEqual(frame.origin.x, 0)
    }
}
