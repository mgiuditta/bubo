import SwiftUI

/// Cold graphite, with the active Tinta at most at 6% in a single radial around the Orb (design system).
struct HUDBackground: View {
    @AppStorage(OrbColor.defaultsKey) private var orbColor = OrbColor.automatic

    var body: some View {
        ZStack {
            Palette.ink
            RadialGradient(
                colors: [Color(orbColor.tinta(for: OrbControls.shared.provider).base, opacity: 0.06), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: 640
            )
        }
        .ignoresSafeArea()
    }
}
