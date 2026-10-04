import SwiftUI

/// Impostazioni › Modelli: GitHub Copilot (ADR 0012), the preferences for each Tipo, the OpenAI-compatible endpoints "Rifai con…" offers besides
/// Claude (spec 10), and the PriceTable their Spesa is estimated with (spec 18).
struct ModelsSettingsView: View {
    @State private var settings = EndpointSettings.shared
    @State private var prices = PriceTable.shared
    @State private var preferences = TypePreferences.shared
    @AppStorage(QuotaThresholds.stepDownKey) private var stepDown = QuotaThresholds().stepDown
    @AppStorage(QuotaThresholds.onMacKey) private var onMac = QuotaThresholds().onMac
    @State private var newName = ""
    @State private var newAddress = ""

    var body: some View {
        Form {
            Section {
                Text("Le Domande vanno a Claude. Qui scegli gli altri modelli che «Rifai con…» propone: scrivi l'id del modello come lo chiama il fornitore. Bubo li chiama direttamente dal Mac, senza passare da altri server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            CopilotSettingsSection()
            // Next to Copilot's account: the two read together.
            CopilotConsentSection(settings: settings)
            TypePreferencesSection(preferences: preferences, settings: settings)
            Section {
                Picker("Modello locale", selection: localModelBinding) {
                    Text("Nessuno").tag(String?.none)
                    ForEach(settings.ready.filter(\.isOnMac)) { endpoint in
                        Text(verbatim: "\(endpoint.name) · \(endpoint.model)").tag(Optional(endpoint.id))
                    }
                }
            } footer: {
                Text("Senza rete le Domande vanno al Modello locale invece che a Claude; se non risponde, ad Apple FM. In nessun altro caso Bubo lo sceglie da solo.")
            }
            Section {
                Stepper(value: $stepDown, in: 0.5...0.95, step: 0.05) {
                    Text("Modello più leggero oltre: \(Self.percent(stepDown))")
                }
                Stepper(value: $onMac, in: 0.5...1, step: 0.05) {
                    Text("Domande sul Mac oltre: \(Self.percent(onMac))")
                }
            } header: {
                Text("Quota di 5 ore")
            } footer: {
                Text("Oltre la prima soglia le scelte automatiche scendono di un gradino; oltre la seconda le Domande vanno al Modello locale o ad Apple FM. Le Sessioni restano su Claude, le tue scelte valgono sempre e niente si blocca. Con la API key non vale.")
            }
            ForEach(settings.endpoints) { endpoint in
                EndpointSection(endpoint: endpoint, settings: settings)
            }
            Section {
                TextField("Nome", text: $newName)
                TextField("Indirizzo", text: $newAddress, prompt: Text(verbatim: "https://api.x.ai/v1"))
                Button("Aggiungi", action: addEndpoint)
                    .disabled(newEndpointURL == nil || newName.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Altro endpoint compatibile con OpenAI")
            }
            Section {
                Toggle("Aggiorna i prezzi ogni giorno", isOn: $prices.updatesDaily)
            } header: {
                Text("Prezzi")
            } footer: {
                Text("Con i prezzi di models.dev Bubo stima la spesa di OpenAI, Gemini e xAI sulla tua chiave. L'aggiornamento scarica solo la tabella: non manda niente di tuo. Prezzi del \(prices.snapshot.date.formatted(date: .long, time: .omitted)).")
            }
        }
        .formStyle(.grouped)
    }

    /// A threshold as the settings show it, such as «80%».
    private static func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }

    private var localModelBinding: Binding<String?> {
        Binding {
            settings.localModel?.id
        } set: { id in
            settings.setLocalModel(settings.ready.first { $0.id == id })
        }
    }

    private var newEndpointURL: URL? {
        guard let url = URL(string: newAddress.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https" || url.scheme == "http", url.host() != nil
        else { return nil }
        return url
    }

    private func addEndpoint() {
        guard let url = newEndpointURL else { return }
        settings.save(.custom(named: newName.trimmingCharacters(in: .whitespaces), at: url))
        newName = ""
        newAddress = ""
    }
}

#Preview {
    ModelsSettingsView()
        .frame(width: 480, height: 600)
}
