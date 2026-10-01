import SwiftUI

/// The right side of the Palette: the message found, with the one before and the one after it, or the section of a
/// note found, or the shortcut of a command.
struct PalettePreview: View {
    /// The title of the chosen row; `nil` when nothing is chosen.
    let title: String?
    let messages: [SearchHit]
    /// The message or section found, highlighted among `messages`.
    let found: SearchHit?
    let words: [String]
    /// A line under the title.
    var detail: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.small) {
                if let title {
                    Text(verbatim: title)
                        .font(Typography.body(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    if let detail {
                        Text(verbatim: detail)
                            .font(Typography.body(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(messages.indices, id: \.self) { index in
                        message(messages[index], isFound: isFound(messages[index]))
                    }
                }
            }
            .padding(Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Anteprima"))
    }

    /// Whether `hit` is the message, or the section of a note, that was found.
    private func isFound(_ hit: SearchHit) -> Bool {
        guard let found else { return false }
        return found.message == nil ? hit == found : hit.message?.id == found.message?.id
    }

    private func message(_ hit: SearchHit, isFound: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            if let message = hit.message {
                Text(message.isFromUser ? "Tu" : "Claude")
                    .font(Typography.mono(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textSecondary)
            }
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
