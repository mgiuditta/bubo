import SwiftUI

/// The proposal, made once, to use the model found in Ollama or LM Studio for Fatto breve and Riassunto (spec 10).
struct LocalModelInvitation: View {
    let offer: LocalModelDetector.Offer
    /// Makes the model the Modello locale and the preference of the two Tipi.
    let accept: () -> Void
    /// Lets the proposal go, for good.
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text("Hai \(offer.endpoint.name) con \(offer.model): usarlo per \(String(localized: RequestType.shortFact.label)) e \(String(localized: RequestType.summary.label))?",
                     comment: "Proposal of the Modello locale: the server (Ollama, LM Studio), the model id, then the two Tipi di richiesta.")
                    .font(Typography.body(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Risponde sul Mac, gratis, anche senza rete. Lo cambi in Impostazioni › Modelli.")
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.small)
            Button("Usalo", action: accept)
            Button("No, grazie", action: dismiss)
        }
        .padding(Spacing.small)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question.localModelInvitation")
    }
}

#Preview {
    LocalModelInvitation(offer: .init(endpoint: OpenAICompatibleEndpoint.known[3], model: "llama3.2:latest"),
                         accept: {}, dismiss: {})
        .padding()
        .background(Palette.ink)
}
