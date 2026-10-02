import SwiftUI

/// Impostazioni › Modelli: the OpenAI-compatible endpoints "Rifai con…" offers besides Claude (spec 10).
struct ModelsSettingsView: View {
    @State private var settings = EndpointSettings.shared
    @State private var newName = ""
    @State private var newAddress = ""

    var body: some View {
        Form {
            Section {
                Text("Le Domande vanno a Claude. Qui scegli gli altri modelli che «Rifai con…» propone: scrivi l'id del modello come lo chiama il fornitore. Bubo li chiama direttamente dal Mac, senza passare da altri server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
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
