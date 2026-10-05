import SwiftUI

/// The first step of the onboarding (ADR 0014): three cards, Claude, Copilot and Entrambi, each with what Bubo found
/// and the remedy when it is not ready; Copilot's consent when the card chosen includes it; Continua once the Motore
/// chosen is ready.
///
/// No window and no sheet, as the rest of the onboarding: the consent is asked inline.
struct EngineStep: View {
    let flow: OnboardingFlow
    /// Whether the notes of the Secondo cervello go to Copilot too, once allowed.
    @State private var sharesNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ForEach(OnboardingFlow.EngineOption.allCases, id: \.self) { option in
                EngineCard(flow: flow, option: option)
            }
            if flow.needsCopilotConsent { consent }
            HStack {
                Spacer()
                Button("Continua", action: flow.confirmEngine)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!flow.canConfirmEngine)
                    .accessibilityIdentifier("onboarding.engine.continue")
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.engine")
    }

    /// Copilot's consent, asked here once and not at the first Domanda (ADR 0014), with the notes of the Secondo
    /// cervello as an option.
    private var consent: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("Mandare Domande e file dei Progetti a GitHub Copilot?")
                .font(Typography.body(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            CopilotTrainingNotice()
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $sharesNotes) {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text("Anche le note del Secondo cervello")
                        .font(Typography.body(size: 13))
                        .foregroundStyle(Palette.textPrimary)
                    Text("Profilo, Regole e le note che Copilot cerca. Può anche scriverne di nuove, e ogni modifica si può annullare.")
                        .font(Typography.body(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            HStack(spacing: Spacing.small) {
                Button("Consenti") { flow.allowCopilot(sharingNotes: sharesNotes) }
                    .accessibilityIdentifier("onboarding.engine.allowCopilot")
                Text("Lo cambi quando vuoi in Impostazioni › Modelli.")
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay { RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.engine.consent")
    }
}

#Preview {
    let flow = OnboardingFlow(hasSessions: false, defaults: UserDefaults(suiteName: "preview") ?? .standard,
                              settings: EndpointSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard)) { _, _ in UUID() }
    flow.readiness = .missing
    flow.copilotReadiness = .ready(version: "1.0.16", account: "ada")
    flow.chooseEngine(.copilot)
    return EngineStep(flow: flow)
        .padding()
        .background(Palette.ink)
}
