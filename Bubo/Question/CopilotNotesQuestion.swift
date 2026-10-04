import SwiftUI

/// The question Bubo asks once, before the notes of the Secondo cervello first go to Copilot (#678): the Domanda waits
/// for the answer, and goes either way.
struct CopilotNotesQuestion: View {
    /// Allows the notes for good and sends the Domanda with them.
    let allow: () -> Void
    /// Sends the Domanda as before, without the notes, and Bubo does not ask again.
    let decline: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: "brain")
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text("Usare le tue note con Copilot?")
                    .font(Typography.body(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Copilot riceve Profilo e Regole del Secondo cervello, le note che cerca, e può scriverne di nuove: ogni scrittura si annulla. Lo cambi in Impostazioni › Modelli.")
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.small)
            Button("Consenti e invia", action: allow)
            Button("Invia senza note", action: decline)
        }
        .padding(Spacing.small)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question.copilotNotes")
    }
}

#Preview {
    CopilotNotesQuestion(allow: {}, decline: {})
        .padding()
        .background(Palette.ink)
}
