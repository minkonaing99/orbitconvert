import CoreGraphics

struct FloatingScreen: Sendable {
    let frame: CGRect
    let visibleFrame: CGRect

    nonisolated init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

enum FloatingRadialPlacement {
    nonisolated static func frame(near pointer: CGPoint, size: CGSize, screens: [FloatingScreen]) -> CGRect? {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite,
              let screen = screens.first(where: { $0.frame.contains(pointer) })
                ?? screens.min(by: { distanceSquared(to: $0.frame, from: pointer)
                                     < distanceSquared(to: $1.frame, from: pointer) }) else { return nil }
        let visible = screen.visibleFrame
        guard visible.width >= size.width, visible.height >= size.height else { return nil }
        let width = size.width
        let height = size.height
        let x = min(max(pointer.x - width / 2, visible.minX), visible.maxX - width)
        let y = min(max(pointer.y - height / 2, visible.minY), visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    nonisolated private static func distanceSquared(to rect: CGRect, from point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
