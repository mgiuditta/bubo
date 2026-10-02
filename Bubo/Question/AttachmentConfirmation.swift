import SwiftUI

/// The confirmation asked before the Allegati of a Domanda go to a provider in the cloud that is not Claude: each chip
/// says "allegato → <fornitore>", and nothing of them leaves before "Invia" (spec 09, Allegati e fornitori).
struct AttachmentConfirmation: View {
    /// The Allegati not confirmed yet for `endpoint`.
    let attachments: [Allegato]
    let endpoint: OpenAICompatibleEndpoint
    /// Confirms every Allegato in `attachments` and sends.
    let send: () -> Void
    /// Asks Claude instead, which reads the Allegati from their path.
    let askClaude: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            AttachmentChips(attachments: attachments, recipient: endpoint.name, remove: nil)
            Text("Il testo di questi allegati esce dal Mac e va a \(endpoint.name).")
                .font(Typography.body(size: 13))
                .foregroundStyle(Palette.textSecondary)
            HStack(spacing: Spacing.small) {
                Button("Invia a \(endpoint.name)", action: send)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("question.attachments.send")
                Button("Chiedi a Claude", action: askClaude)
                Button("Annulla", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.small)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question.attachments.confirmation")
    }
}

#Preview {
    AttachmentConfirmation(attachments: [Allegato(name: "Nota", text: "Testo trascinato")],
                           endpoint: OpenAICompatibleEndpoint.known[0], send: {}, askClaude: {}, cancel: {})
        .padding()
        .background(Palette.ink)
}
