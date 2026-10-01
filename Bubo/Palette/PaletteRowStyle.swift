import SwiftUI

extension View {
    /// The look of a row of the Palette: padded, with a background and a border when it is the chosen one; for
    /// VoiceOver one button, selected when chosen, labelled by the row.
    func paletteRowStyle(isSelected: Bool) -> some View {
        padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Palette.surface : .clear, in: .rect(cornerRadius: CornerRadius.medium))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: CornerRadius.medium).strokeBorder(Palette.lineStrong)
                }
            }
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
