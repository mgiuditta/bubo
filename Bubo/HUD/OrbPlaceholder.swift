import SwiftUI

/// A static stand-in for the Metal Orb, framed by the HUD rings.
// ponytail: sostituito dal renderer Metal della fase 2 (mappa fase 1–2, Blob in Metal nel Panel).
struct OrbPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    @AppStorage(Motion.reducesMotionKey) private var reducesMotion = false

    var body: some View {
        ZStack {
            HUDRings(isAnimated: !(systemReducesMotion || reducesMotion))
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.accentStrong, Palette.accent, Color(hex: 0x3A170D)],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .padding(90)
                .shadow(color: Palette.accent.opacity(0.35), radius: 60)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Orb di Bubo, a riposo")
        .accessibilityAddTraits(.isImage)
    }
}
