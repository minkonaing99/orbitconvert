import AppKit
import SwiftUI

struct RadialMenuView: View {
    let file: FileItem
    let actions: [FileAction]
    let onSelect: (FileAction) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var hoveredIndex: Int?
    @State private var selectedIndex: Int?

    private let diameter = 360.0
    private var geometry: RadialMenuGeometry {
        RadialMenuGeometry(count: actions.count, innerRadius: 86, outerRadius: 166)
    }
    private var center: CGPoint { CGPoint(x: diameter / 2, y: diameter / 2) }

    var body: some View {
        VStack(spacing: 10) {
            if actions.isEmpty {
                Text("No conversion actions available")
                    .foregroundStyle(.secondary)
            } else {
                menu
            }
            Button("Close menu") { onDismiss() }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conversion menu for \(file.fileName)")
        .accessibilityAction(.escape, onDismiss)
        .onExitCommand(perform: onDismiss)
        .accessibilityActions {
            ForEach(actions) { action in
                Button("Convert to \(action.title)") { onSelect(action) }
            }
        }
    }

    private var menu: some View {
        ZStack {
            ForEach(actions.indices, id: \.self) { index in
                RadialSegmentShape(geometry: geometry, index: index)
                    .fill(index == hoveredIndex ? Color.accentColor.opacity(0.42) :
                          index == selectedIndex ? Color.accentColor.opacity(0.23) : Color.primary.opacity(0.06))
                    .overlay {
                        RadialSegmentShape(geometry: geometry, index: index)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    }
                let labelPoint = geometry.point(angle: geometry.angle(for: index), radius: 126, center: center)
                VStack(spacing: 3) {
                    Image(systemName: actions[index].symbolName)
                        .font(.title3)
                    Text(actions[index].title)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(index == hoveredIndex ? Color.accentColor : Color.primary)
                .position(labelPoint)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            VStack(spacing: 5) {
                if let thumbnail = NSImage(data: file.thumbnailData) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .accessibilityHidden(true)
                }
                Text(file.fileName)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 110)
                Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 158, height: 158)
            .background(.thickMaterial, in: Circle())
            .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            let index: Int?
            switch phase {
            case .active(let point): index = geometry.hitTest(point, center: center)
            case .ended: index = nil
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { hoveredIndex = index }
        }
        .simultaneousGesture(SpatialTapGesture().onEnded { event in
            guard let index = geometry.hitTest(event.location, center: center) else { return }
            onSelect(actions[index])
        })
        .focusable()
        .focused($isFocused)
        .onAppear {
            selectedIndex = actions.isEmpty ? nil : 0
            isFocused = true
        }
        .onKeyPress { press in
            switch press.key {
            case .leftArrow, .upArrow: moveSelection(by: -1)
            case .rightArrow, .downArrow: moveSelection(by: 1)
            case .return:
                if let selectedIndex, actions.indices.contains(selectedIndex) { onSelect(actions[selectedIndex]) }
            case .escape: onDismiss()
            default: return .ignored
            }
            return .handled
        }
        .accessibilityValue(selectedIndex.flatMap { actions.indices.contains($0) ? "Selected \(actions[$0].title)" : nil } ?? "No selection")
        .onChange(of: actions.count) { _, count in
            selectedIndex = count == 0 ? nil : min(selectedIndex ?? 0, count - 1)
        }
    }

    private func moveSelection(by offset: Int) {
        guard !actions.isEmpty else { return }
        let next = ((selectedIndex ?? 0) + offset + actions.count) % actions.count
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { selectedIndex = next }
    }
}

private struct RadialSegmentShape: InsettableShape {
    let geometry: RadialMenuGeometry
    let index: Int
    var insetAmount = 0.0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += Double(amount)
        return copy
    }

    func path(in rect: CGRect) -> Path {
        guard geometry.count > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let half = geometry.anglePerItem / 2
        let start = geometry.angle(for: index) - half
        let end = geometry.angle(for: index) + half
        let inner = geometry.innerRadius + insetAmount
        let outer = geometry.outerRadius - insetAmount
        let steps = max(12, 64 / geometry.count)
        var path = Path()
        path.move(to: geometry.point(angle: start, radius: inner, center: center))
        for step in 0...steps {
            let angle = start + (end - start) * Double(step) / Double(steps)
            path.addLine(to: geometry.point(angle: angle, radius: outer, center: center))
        }
        for step in (0...steps).reversed() {
            let angle = start + (end - start) * Double(step) / Double(steps)
            path.addLine(to: geometry.point(angle: angle, radius: inner, center: center))
        }
        path.closeSubpath()
        return path
    }
}
