import SwiftUI

/// The brand mark across the top of the HUD: a moon-colored disc, achromatic like the mark (design system).
struct HUDHeader: View {
    var body: some View {
        HStack(spacing: Spacing.small) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.markLight, Palette.textSecondary, Palette.markDark],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 14
                    )
                )
                .frame(width: 22, height: 22)
                .overlay { Circle().strokeBorder(Palette.lineStrong, lineWidth: 0.5) }
                .accessibilityHidden(true)
            Text("BUBO")
                .font(Typography.display(size: 20))
                .tracking(8.4)
                .accessibilityLabel("Bubo")
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
