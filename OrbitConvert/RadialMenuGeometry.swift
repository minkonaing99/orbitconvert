import CoreGraphics
import Foundation

struct RadialMenuGeometry: Sendable {
    let count: Int
    let innerRadius: Double
    let outerRadius: Double

    nonisolated init(count: Int, innerRadius: Double, outerRadius: Double) {
        self.count = count
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
    }

    nonisolated var anglePerItem: Double {
        count > 0 ? 2 * Double.pi / Double(count) : 0
    }

    nonisolated func angle(for index: Int) -> Double {
        Double(index) * anglePerItem
    }

    nonisolated func point(angle: Double, radius: Double, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + CGFloat(radius * sin(angle)), y: center.y - CGFloat(radius * cos(angle)))
    }

    nonisolated func hitTest(_ location: CGPoint, center: CGPoint) -> Int? {
        guard count > 0, innerRadius >= 0, outerRadius > innerRadius else { return nil }
        let dx = Double(location.x - center.x)
        let dy = Double(location.y - center.y)
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }
        let angle = atan2(dx, -dy)
        let normalized = angle < 0 ? angle + 2 * Double.pi : angle
        return Int(floor((normalized + anglePerItem / 2) / anglePerItem)) % count
    }
}
