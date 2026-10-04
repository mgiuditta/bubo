import SwiftUI

/// The preferences "Usa sempre per «Tipo»" set, in Impostazioni › Modelli: who answers each Tipo, and the way back
/// to its default (spec 10).
struct TypePreferencesSection: View {
    let preferences: TypePreferences
    let settings: EndpointSettings

    var body: some View {
        Section {
            ForEach(RequestType.allCases.filter { preferences.choices[$0] != nil }, id: \.self) { type in
                if let choice = preferences.choices[type] {
                    LabeledContent {
                        Button("Togli") { preferences.remove(for: type) }
                            .accessibilityLabel("Togli la preferenza per \(String(localized: type.label))")
                    } label: {
                        Text(type.label)
                        Text(verbatim: name(of: choice))
                        if let pause = pause(of: choice) {
                            Text(pause)
                        }
                    }
                }
            }
        } header: {
            Text("Preferenze per le Domande")
        } footer: {
            if preferences.choices.isEmpty {
                Text("Nessuna preferenza. Per mandare sempre un tipo di Domanda allo stesso modello, spunta «Usa sempre per» in «Rifai con…».")
            }
        }
    }

    /// The model the Tipo goes to, as the reason line names it.
    private func name(of choice: TypePreference) -> String {
        switch choice {
        case let .claude(step): return step.name
        case let .endpoint(id):
            guard let endpoint = settings.endpoints.first(where: { $0.id == id }) else { return id }
            return endpoint.model.isEmpty ? endpoint.name : "\(endpoint.name) · \(endpoint.model)"
        case let .copilot(_, name):
            return String(localized: "\(name) via Copilot",
                          comment: "A model of the user's GitHub Copilot plan, such as «GPT-6 via Copilot», or where it runs, such as «OpenAI via Copilot».")
        }
    }

    /// Why the preference does not answer now, and the Tipo takes its default; `nil` when it answers.
    private func pause(of choice: TypePreference) -> LocalizedStringResource? {
        guard case let .endpoint(id) = choice else { return nil }
        guard let endpoint = settings.endpoints.first(where: { $0.id == id }) else { return nil }
        if endpoint.model.trimmingCharacters(in: .whitespaces).isEmpty {
            return LocalizedStringResource("In pausa: scegli un modello per \(endpoint.name).")
        }
        if !endpoint.isOnMac, !settings.consents.contains(id) {
            return LocalizedStringResource("In pausa: \(endpoint.name) non ha il tuo consenso. Te lo chiede «Rifai con…» quando lo scegli.")
        }
        return nil
    }
}
