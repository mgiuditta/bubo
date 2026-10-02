import SwiftUI

/// One OpenAI-compatible endpoint in Impostazioni › Modelli: its model, its address, its key and its consent.
struct EndpointSection: View {
    let endpoint: OpenAICompatibleEndpoint
    let settings: EndpointSettings
    @State private var model = ""
    @State private var address = ""
    @State private var hasKey: Bool?
    @State private var isEnteringKey = false
    @State private var keyFailure: String?
    @State private var connecting: Task<Void, Never>?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            TextField("Modello", text: $model)
                .onSubmit(saveFields)
            if ![.openAI, .gemini, .openRouter].contains(endpoint.kind) {
                TextField("Indirizzo", text: $address)
                    .onSubmit(saveFields)
            }
            if endpoint.kind == .openRouter {
                openRouterRow
            } else if !endpoint.isOnMac {
                keyRow
            }
            if endpoint.kind == .gemini {
                Toggle("Il progetto della chiave ha la fatturazione attiva", isOn: billingBinding)
                Text("Senza fatturazione Google usa le Domande per addestrare i suoi modelli, e in Europa non è ammesso: Bubo non manda niente. Lo vedi nella pagina Projects di Google AI Studio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !endpoint.isOnMac {
                consentRow
            }
            if endpoint.kind == .custom {
                Button("Rimuovi \(endpoint.name)", role: .destructive) { settings.remove(endpoint) }
            }
        } header: {
            Text(verbatim: endpoint.name)
        } footer: {
            if endpoint.isOnMac {
                Text("Gira sul Mac: la Domanda non lo lascia ed è gratis.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            model = endpoint.model
            address = endpoint.baseURL.absoluteString
            await refreshKey()
        }
        .onDisappear {
            saveFields()
            connecting?.cancel()
        }
        .sheet(isPresented: $isEnteringKey) {
            APIKeySheet(placeholder: keyPlaceholder) { key in
                Task { await saveKey(key) }
            }
        }
    }

    @ViewBuilder
    private var keyRow: some View {
        switch hasKey {
        case true?:
            LabeledContent("Chiave salvata nel Portachiavi") {
                Button("Rimuovi") { Task { await removeKey() } }
            }
        case false?:
            Button("Aggiungi la chiave…") { isEnteringKey = true }
                .buttonStyle(.link)
        case nil:
            EmptyView()
        }
        if let keyFailure {
            Text(keyFailure)
                .font(.callout)
                .foregroundStyle(Palette.danger)
        }
    }

    /// OpenRouter gives its key through the browser (OAuth PKCE), so there is nothing to paste; it has no API to
    /// revoke it, so disconnecting forgets it and links to OpenRouter's keys page (preflight of #95).
    @ViewBuilder
    private var openRouterRow: some View {
        switch hasKey {
        case true?:
            LabeledContent("Collegato, chiave nel Portachiavi") {
                Button("Scollega") { Task { await removeKey() } }
            }
            Link("Revoca la chiave «Bubo» su OpenRouter", destination: URL(string: "https://openrouter.ai/settings/keys")!)
        case false? where connecting != nil:
            LabeledContent {
                Button("Annulla") { connecting?.cancel() }
            } label: {
                LoadingLabel("Autorizza Bubo nel browser…")
            }
        case false?:
            Button("Collega OpenRouter…", action: connectOpenRouter)
        case nil:
            EmptyView()
        }
        if let keyFailure {
            Text(keyFailure)
                .font(.callout)
                .foregroundStyle(Palette.danger)
        }
        Text("Si paga con i tuoi crediti OpenRouter. Se su OpenRouter usi anche chiavi tue (BYOK), attiva «Never use shared capacity» su ciascuna: altrimenti, quando una fallisce, OpenRouter ripiega da solo sui suoi crediti.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var consentRow: some View {
        if settings.consents.contains(endpoint.id) {
            LabeledContent("Può ricevere il testo delle Domande") {
                Button("Revoca") { settings.revokeConsent(of: endpoint) }
            }
        } else {
            Text("La prima volta che lo scegli in «Rifai con…» Bubo ti chiede il consenso. Riceve solo il testo della Domanda, mai file o memoria dei Progetti.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var billingBinding: Binding<Bool> {
        Binding {
            settings.endpoints.first { $0.id == endpoint.id }?.confirmsBilling ?? false
        } set: { confirmed in
            var updated = settings.endpoints.first { $0.id == endpoint.id } ?? endpoint
            updated.confirmsBilling = confirmed
            settings.save(updated)
        }
    }

    private var keyPlaceholder: String {
        switch endpoint.kind {
        case .openAI: "sk-…"
        case .gemini: "AIza…"
        case .openRouter, .ollama, .lmStudio, .custom: ""
        }
    }

    private var keys: APIKeyStore { APIKeyStore(account: endpoint.keychainAccount) }

    private func saveFields() {
        var updated = settings.endpoints.first { $0.id == endpoint.id } ?? endpoint
        updated.model = model.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: address.trimmingCharacters(in: .whitespaces)), url.scheme != nil, url.host() != nil {
            updated.baseURL = url
        }
        guard updated != settings.endpoints.first(where: { $0.id == endpoint.id }) else { return }
        settings.save(updated)
    }

    private func refreshKey() async {
        do {
            hasKey = try await keys.containsKey()
        } catch {
            keyFailure = error.localizedDescription
        }
    }

    private func saveKey(_ key: String) async {
        do {
            try await keys.save(key)
            keyFailure = nil
            hasKey = true
        } catch {
            keyFailure = error.localizedDescription
        }
    }

    private func connectOpenRouter() {
        keyFailure = nil
        connecting = Task {
            defer { connecting = nil }
            do {
                try await OpenRouterAuthorization.connect(open: { openURL($0) }) { key in
                    try await keys.save(key)
                }
                hasKey = true
            } catch is CancellationError {
            } catch OAuthCallbackServer.Failure.timedOut {
                keyFailure = String(localized: "Il collegamento è scaduto: riprova e autorizza Bubo entro 10 minuti.")
            } catch {
                keyFailure = String(localized: "OpenRouter non ha dato la chiave: riprova.")
            }
        }
    }

    private func removeKey() async {
        do {
            try await keys.delete()
            keyFailure = nil
            hasKey = false
        } catch {
            keyFailure = error.localizedDescription
        }
    }
}
