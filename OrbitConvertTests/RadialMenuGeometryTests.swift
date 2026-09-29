import CoreGraphics
import XCTest
@testable import OrbitConvert

final class RadialMenuGeometryTests: XCTestCase {
    private let center = CGPoint(x: 180, y: 180)

    func testEmptyMenuHasNoHit() {
        let geometry = RadialMenuGeometry(count: 0, innerRadius: 70, outerRadius: 160)
        XCTAssertNil(geometry.hitTest(CGPoint(x: 180, y: 60), center: center))
    }

    func testOneItemOwnsTheWholeRing() {
        let geometry = RadialMenuGeometry(count: 1, innerRadius: 70, outerRadius: 160)
        for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 4) {
            XCTAssertEqual(geometry.hitTest(geometry.point(angle: angle, radius: 110, center: center), center: center), 0)
        }
    }

    func testEverySegmentCenterMatchesHitTesting() {
        for count in [2, 3, 4, 8, 12] {
            let geometry = RadialMenuGeometry(count: count, innerRadius: 70, outerRadius: 160)
            for index in 0..<count {
                let point = geometry.point(angle: geometry.angle(for: index), radius: 115, center: center)
                XCTAssertEqual(geometry.hitTest(point, center: center), index)
            }
        }
    }

    func testInnerAndOuterRadiusAreInclusive() {
        let geometry = RadialMenuGeometry(count: 4, innerRadius: 70, outerRadius: 160)
        XCTAssertNil(geometry.hitTest(center, center: center))
        XCTAssertNil(geometry.hitTest(geometry.point(angle: 0, radius: 69, center: center), center: center))
        XCTAssertEqual(geometry.hitTest(geometry.point(angle: 0, radius: 70, center: center), center: center), 0)
        XCTAssertEqual(geometry.hitTest(geometry.point(angle: 0, radius: 160, center: center), center: center), 0)
        XCTAssertNil(geometry.hitTest(geometry.point(angle: 0, radius: 161, center: center), center: center))
    }

    func testSegmentBoundaryAndWraparound() {
        let geometry = RadialMenuGeometry(count: 4, innerRadius: 70, outerRadius: 160)
        let boundary = Double.pi / 4
        XCTAssertEqual(geometry.hitTest(geometry.point(angle: boundary - 0.01, radius: 115, center: center), center: center), 0)
        XCTAssertEqual(geometry.hitTest(geometry.point(angle: boundary, radius: 115, center: center), center: center), 1)
        XCTAssertEqual(geometry.hitTest(geometry.point(angle: boundary + 0.01, radius: 115, center: center), center: center), 1)
        XCTAssertEqual(geometry.hitTest(geometry.point(angle: -Double.pi / 2, radius: 115, center: center), center: center), 3)
        XCTAssertEqual(geometry.hitTest(geometry.point(angle: 2 * Double.pi - 0.01, radius: 115, center: center), center: center), 0)
    }
}
