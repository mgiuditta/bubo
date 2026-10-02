import SwiftUI

/// The dotted outer ring and the ticked inner ring, turning slowly in opposite directions.
///
/// Each ring is drawn once and turned with `rotationEffect`, so a frame only changes a transform:
/// redrawing the `Canvas` every frame kept about 200 MB of textures alive (#287).
struct HUDRings: View {
    /// Whether the rings turn; off with Reduce Motion.
    var isAnimated: Bool

    var body: some View {
        TimelineView(.animation(paused: !isAnimated)) { context in
            let seconds = isAnimated ? context.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                DottedRing()
                    .rotationEffect(.degrees(seconds / Motion.outerRingPeriod * 360))
                TickedRing()
                    .rotationEffect(.degrees(-seconds / Motion.innerRingPeriod * 360))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The outer ring: a dotted circle.
private struct DottedRing: View {
    var body: some View {
        Canvas { canvas, size in
            let radius = min(size.width, size.height) * 0.465
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            canvas.stroke(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(Palette.lineStrong),
                style: StrokeStyle(lineWidth: 0.8, dash: [1, 5])
            )
        }
    }
}

/// The inner ring: 120 ticks, a longer one every ten.
private struct TickedRing: View {
    var body: some View {
        Canvas { canvas, size in
            let radius = min(size.width, size.height) * 0.44
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var ticks = Path()
            for index in 0..<120 {
                let angle = Double(index) / 120 * 2 * .pi
                let length: CGFloat = index.isMultiple(of: 10) ? 8 : 3
                let direction = CGPoint(x: cos(angle), y: sin(angle))
                ticks.move(to: CGPoint(x: center.x + direction.x * radius, y: center.y + direction.y * radius))
                ticks.addLine(to: CGPoint(x: center.x + direction.x * (radius - length),
                                          y: center.y + direction.y * (radius - length)))
            }
            canvas.stroke(ticks, with: .color(Palette.lineStrong), lineWidth: 0.8)
        }
    }
}
