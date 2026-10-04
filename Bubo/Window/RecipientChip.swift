import SwiftUI

/// The chip at the start of the composer that says who the text goes to: the Cervello or a Progetto.
struct RecipientChip: View {
    let recipient: Recipient

    var body: some View {
        Text(recipient.name)
            .font(.buboInterface.weight(.medium))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .overlay(Capsule().strokeBorder(Palette.lineStrong))
            .accessibilityLabel(recipient.accessibilityLabel)
            .accessibilityIdentifier("recipient")
    }
}
