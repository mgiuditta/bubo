import SwiftUI

/// The brand mark across the top of the HUD: the moon-colored owl on a graphite disc, achromatic like the mark
/// (design system).
struct HUDHeader: View {
    var body: some View {
        HStack(spacing: Spacing.small) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.markDark, Palette.ink],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 14
                    )
                )
                .overlay {
                    Image("MenuBarGlyph")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Palette.markLight, Palette.textSecondary],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(3)
                }
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
