import SwiftUI

/// "Rifai con…" (⌘⇧↑): the models near the one that answered, each with where it runs, its first token and its cost
/// (spec 10, Interfaccia).
struct RetryWithList: View {
    let alternatives: [RetryAlternative]
    /// The endpoints the user left out for this Domanda, by not giving their consent.
    let excluded: [OpenAICompatibleEndpoint]
    /// Whether `claude` runs with the API key, paid per use, rather than the subscription.
    let usesAPIKey: Bool
    /// The Tipo di richiesta of the Domanda, which "Usa sempre per «Tipo»" names; `nil` when it was not decided.
    let type: RequestType?
    /// Whether the model picked becomes the preference of `type`, for all the Domande.
    @Binding var alwaysUse: Bool
    let pick: (RetryAlternative) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("Rifai con…")
                .font(Typography.body(size: 12).weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            if alternatives.isEmpty {
                Text("Nessun altro modello vicino. Aggiungine uno in Impostazioni › Modelli.")
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(alternatives) { alternative in
                Button { pick(alternative) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: name(of: alternative))
                            .font(Typography.body(size: 13))
                            .foregroundStyle(Palette.textPrimary)
                        Text(details(of: alternative))
                            .font(Typography.body(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
            if let type, !alternatives.isEmpty {
                Toggle("Usa sempre per «\(String(localized: type.label))»", isOn: $alwaysUse)
                    .toggleStyle(.checkbox)
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .help("Le prossime Domande di \(String(localized: type.label)) vanno al modello che scegli qui. Puoi togliere la preferenza in Impostazioni › Modelli.")
            }
            ForEach(excluded) { endpoint in
                Text("\(endpoint.name) è escluso per questa Domanda: non hai dato il consenso.")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(Spacing.small)
        .frame(width: 300, alignment: .leading)
    }

    /// The model, as the reason line names it: «Opus · alto», or the endpoint and its model id.
    private func name(of alternative: RetryAlternative) -> String {
        switch alternative.target {
        case let .claude(step):
            guard let effort = step.effort else { return step.family.name }
            return String(localized: "\(step.family.name) · \(String(localized: effort.label))",
                          comment: "Model and effort in the reason line, such as «Sonnet 5.5 · medio».")
        case let .endpoint(endpoint):
            return "\(endpoint.name) · \(endpoint.model)"
        }
    }

    /// Where it runs, how long the first token took last time, and what it costs.
    private func details(of alternative: RetryAlternative) -> String {
        let place: String
        let cost: String
        switch alternative.target {
        case .claude:
            place = String(localized: "Anthropic, nel cloud", comment: "Where a Claude model of «Rifai con…» runs.")
            cost = usesAPIKey
                ? String(localized: "a consumo sulla API key", comment: "Cost of a Claude model of «Rifai con…» with the API key.")
                : String(localized: "dalla finestra di 5 ore", comment: "Cost of a Claude model of «Rifai con…» with the subscription.")
        case let .endpoint(endpoint) where endpoint.isOnMac:
            place = String(localized: "sul Mac", comment: "Where a model of «Rifai con…» runs: on this Mac.")
            cost = String(localized: "gratis", comment: "Cost of a model of «Rifai con…» running on this Mac.")
        case let .endpoint(endpoint):
            place = String(localized: "\(endpoint.name), nel cloud", comment: "Where a model of «Rifai con…» runs: another provider's cloud.")
            cost = String(localized: "a consumo sulla tua chiave", comment: "Cost of another provider's model in «Rifai con…», paid on the user's key.")
        }
        guard let firstToken = alternative.firstToken else { return "\(place) · \(cost)" }
        let duration = firstToken.formatted(.units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: 1)))
        let time = String(localized: "primo token in \(duration)",
                          comment: "How long the first token of this model took last time, in «Rifai con…».")
        return "\(place) · \(time) · \(cost)"
    }
}

#Preview {
    var endpoint = OpenAICompatibleEndpoint.known.first { $0.kind == .ollama }!
    endpoint.model = "qwen3:8b"
    var gemini = OpenAICompatibleEndpoint.known[1]
    gemini.model = "gemini-2.5-flash"
    return RetryWithList(alternatives: [
        RetryAlternative(target: .claude(Scala.Step(family: .sonnet, effort: .low)), firstToken: .milliseconds(820)),
        RetryAlternative(target: .claude(Scala.Step(family: .opus, effort: .medium))),
        RetryAlternative(target: .endpoint(endpoint)),
    ], excluded: [gemini], usesAPIKey: false, type: .writing, alwaysUse: .constant(false)) { _ in }
    .background(Palette.ink)
}
