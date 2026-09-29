import SwiftUI

/// The brand mark across the top of the HUD.
struct HUDHeader: View {
    var body: some View {
        HStack(spacing: Spacing.small) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.accentStrong, Palette.accent, Color(hex: 0x6B2C19)],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 14
                    )
                )
                .frame(width: 22, height: 22)
                .shadow(color: Palette.accent.opacity(0.6), radius: 9)
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
