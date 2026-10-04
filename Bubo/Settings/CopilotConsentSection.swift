import SwiftUI

/// Copilot's consent in Impostazioni › Modelli: given or revoked by the user, with the notice on training and the way
/// to GitHub's setting that turns it off (spec 10, ADR 0011).
struct CopilotConsentSection: View {
    let settings: EndpointSettings
    @State private var isAskingConsent = false

    var body: some View {
        Section {
            if settings.allowsCopilot {
                LabeledContent("Copilot può ricevere Domande e file dei Progetti") {
                    Button("Revoca", action: settings.revokeCopilotConsent)
                }
                // Asked once in a Domanda, the first time the notes would go (#678).
                if settings.allowsCopilotNotes {
                    LabeledContent("Copilot può usare le note del Secondo cervello") {
                        Button("Revoca", action: settings.revokeCopilotNotesConsent)
                    }
                } else if settings.hasAskedCopilotNotesConsent {
                    LabeledContent("Copilot non riceve le note del Secondo cervello") {
                        Button("Consenti") { settings.answerCopilotNotesConsent(allowing: true) }
                    }
                }
            } else {
                Text("Senza il tuo consenso Bubo non manda niente a Copilot: né Domande né file dei Progetti.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Consenti…") { isAskingConsent = true }
            }
        } header: {
            Text("Cosa riceve Copilot")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                CopilotTrainingNotice()
                    .foregroundStyle(.secondary)
                Link("Apri le impostazioni di Copilot su GitHub", destination: EndpointSettings.copilotTrainingSettingsURL)
            }
            .font(.callout)
        }
        .copilotConsentDialog(isPresented: $isAskingConsent, settings: settings)
    }
}
