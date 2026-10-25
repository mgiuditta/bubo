import SwiftUI

/// An answer of the Suggeritore: the question small and quiet above, the answer as the conversation shows it.
struct PromptCardView: View {
    let card: PromptCard

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(reasonLabel)
                    .font(.buboData)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textSecondary)
                Text(verbatim: card.question)
                    .font(.buboInterface)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            if let failure = card.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.buboInterface)
                    .foregroundStyle(Palette.danger)
            } else if card.answer.isEmpty {
                ThinkingDots()
            } else {
                AnswerProse(prose: card.answer)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay(RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line))
        .accessibilityElement(children: .contain)
    }

    private var reasonLabel: LocalizedStringKey {
        switch card.reason {
        case .pastQuestion: "Domanda"
        case .lastQuestion: "Ultima domanda"
        case .typed: "Scritta"
        }
    }
}
