import SwiftUI

/// One message of the Cronologia window: who wrote it, then its text; the point found is highlighted and marked.
struct TranscriptLineView: View {
    let line: TranscriptLine
    let words: [String]
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(spacing: Spacing.xSmall) {
                Text(line.message.isFromUser ? "Tu" : "Claude")
                    .foregroundStyle(Palette.textSecondary)
                if isCurrent {
                    // Not only the colour: the point found says so.
                    Text("Trovato")
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            .font(Typography.mono(size: 10, weight: .medium))
            .textCase(.uppercase)
            HighlightedText(text: line.message.text, words: words)
                .font(Typography.body(size: 13))
                .textSelection(.enabled)
        }
        .padding(Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Palette.surface : .clear, in: .rect(cornerRadius: CornerRadius.small))
        .overlay {
            if isCurrent { RoundedRectangle(cornerRadius: CornerRadius.small).strokeBorder(Palette.lineStrong) }
        }
        .accessibilityElement(children: .combine)
    }
}
