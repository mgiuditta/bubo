import SwiftUI

/// A command in the Palette: its title, and its shortcut on the right when it has one.
struct PaletteCommandRow: View {
    let command: PaletteCommand
    let words: [String]
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            HighlightedText(text: command.title, words: words)
                .font(Typography.body(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: Spacing.xSmall)
            if let shortcut = command.shortcut {
                Text(verbatim: shortcut)
                    .font(Typography.mono(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .paletteRowStyle(isSelected: isSelected)
        .accessibilityLabel(Text(verbatim: command.title))
        .accessibilityValue(command.shortcut ?? "")
        .accessibilityHint(Text("Esegue il comando"))
    }
}
