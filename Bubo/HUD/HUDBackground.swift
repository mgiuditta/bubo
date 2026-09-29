import SwiftUI

/// Warm graphite with two soft ember glows, as in the reference.
struct HUDBackground: View {
    var body: some View {
        ZStack {
            Palette.ink
            RadialGradient(
                colors: [Palette.accent.opacity(0.10), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: 640
            )
            RadialGradient(
                colors: [Palette.accentStrong.opacity(0.05), .clear],
                center: UnitPoint(x: 0.85, y: 1.1),
                startRadius: 0,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}
