import SwiftUI

/// The dotted outer ring and the ticked inner ring, turning slowly in opposite directions.
struct HUDRings: View {
    /// Whether the rings turn; off with Reduce Motion.
    var isAnimated: Bool

    var body: some View {
        TimelineView(.animation(paused: !isAnimated)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let side = min(size.width, size.height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outerRadius = side * 0.465
                let innerRadius = side * 0.44

                var outer = canvas
                outer.translateBy(x: center.x, y: center.y)
                outer.rotate(by: .degrees(isAnimated ? seconds / Motion.outerRingPeriod * 360 : 0))
                outer.stroke(
                    Path(ellipseIn: CGRect(x: -outerRadius, y: -outerRadius, width: outerRadius * 2, height: outerRadius * 2)),
                    with: .color(Palette.accentStrong.opacity(0.16)),
                    style: StrokeStyle(lineWidth: 0.8, dash: [1, 5])
                )

                var inner = canvas
                inner.translateBy(x: center.x, y: center.y)
                inner.rotate(by: .degrees(isAnimated ? -seconds / Motion.innerRingPeriod * 360 : 0))
                var ticks = Path()
                for index in 0..<120 {
                    let angle = Double(index) / 120 * 2 * .pi
                    let length: CGFloat = index.isMultiple(of: 10) ? 8 : 3
                    let direction = CGPoint(x: cos(angle), y: sin(angle))
                    ticks.move(to: CGPoint(x: direction.x * innerRadius, y: direction.y * innerRadius))
                    ticks.addLine(to: CGPoint(x: direction.x * (innerRadius - length), y: direction.y * (innerRadius - length)))
                }
                inner.stroke(ticks, with: .color(Palette.accentStrong.opacity(0.22)), lineWidth: 0.8)
            }
        }
        .accessibilityHidden(true)
    }
}
