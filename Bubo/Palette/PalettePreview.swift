import SwiftUI

/// The right side of the Palette: the message found, with the one before and the one after it.
struct PalettePreview: View {
    let result: ConversationResult?
    let messages: [SearchHit]
    let words: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.small) {
                if let result {
                    Text(verbatim: result.title)
                        .font(Typography.body(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    if result.best == nil {
                        Text("Scrivi per cercare nei messaggi.")
                            .font(Typography.body(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(messages.indices, id: \.self) { index in
                        message(messages[index], isFound: messages[index].message?.id == result.best?.message?.id)
                    }
                }
            }
            .padding(Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Anteprima"))
    }

    private func message(_ hit: SearchHit, isFound: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(hit.message?.isFromUser == true ? "Tu" : "Claude")
                .font(Typography.mono(size: 10, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
            HighlightedText(text: String(hit.text.prefix(1_200)), words: isFound ? words : [])
                .font(Typography.body(size: 12))
                .foregroundStyle(isFound ? Palette.textPrimary : Palette.textSecondary)
        }
        .padding(Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isFound ? Palette.surface : .clear, in: .rect(cornerRadius: CornerRadius.small))
        .overlay {
            if isFound { RoundedRectangle(cornerRadius: CornerRadius.small).strokeBorder(Palette.line) }
        }
        .accessibilityElement(children: .combine)
    }
}
