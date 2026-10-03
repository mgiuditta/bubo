import SwiftUI

/// Impostazioni › Budget (spec 18): the monthly Budgets per provider paid per use, per Progetto and in total, the
/// threshold, the overshoot Bubo allows and where to set a hard limit at the provider.
struct BudgetSettingsView: View {
    @Environment(CostLedger.self) private var ledger
    @State private var settings = BudgetSettings.shared
    @State private var endpoints = EndpointSettings.shared

    var body: some View {
        // Read again at every change of a Budget or of the ledger: the residue is always the current one.
        let budgets = BudgetGuard(budgets: settings.budgets, entries: ledger.entries)
        Form {
            Section {
                Text("Budget mensili sulla Spesa, dal primo del mese nel fuso del Mac. Contano solo i turni passati da Bubo: la riga di comando resta fuori, e l'abbonamento ha già la sua Quota.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Soglia di avviso") {
                    HStack {
                        Slider(value: $settings.budgets.threshold, in: 0.5...0.95, step: 0.05)
                            .accessibilityValue(Text(settings.budgets.threshold, format: .percent.precision(.fractionLength(0))))
                        Text(settings.budgets.threshold, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                }
            } footer: {
                Text("Alla soglia Bubo ti avvisa sotto la risposta e con una notifica, e nelle scelte automatiche usa un altro modello, se c'è. Lo sforamento massimo è un turno per Sessione attiva: il turno che supera il Budget finisce. Per un blocco duro, imposta un limite dal fornitore.")
            }
            Section {
                ForEach(providers, id: \.self) { name in
                    BudgetRow(scope: .provider(name), settings: settings, status: budgets.status(of: .provider(name)),
                              providerLimits: Self.limitsPage(of: name, among: endpoints.endpoints))
                }
            } header: {
                Text("Fornitori")
            } footer: {
                VStack(alignment: .leading) {
                    Text("Se la chiave di OpenRouter ha un limite suo, quando lo raggiungi Bubo mostra quello.")
                    if let copilot = CopilotPriceTable.bundled {
                        Text("La Spesa di GitHub Copilot è una stima: token sul listino GitHub del \(copilot.date.formatted(date: .long, time: .omitted)), 1 credito = $0,01. Bubo non vede i crediti rimasti sul tuo account.")
                    }
                }
            }
            Section("Progetti") {
                if projects.isEmpty {
                    Text("Ancora nessun Progetto con Spesa.")
                        .foregroundStyle(.secondary)
                }
                ForEach(projects, id: \.self) { folder in
                    BudgetRow(scope: .project(folder), settings: settings, status: budgets.status(of: .project(folder)))
                }
            }
            Section("Totale") {
                BudgetRow(scope: .total, settings: settings, status: budgets.status(of: .total))
            }
        }
        .formStyle(.grouped)
    }

    /// Claude, Copilot, the endpoints in a cloud and any provider with a Budget whose endpoint was removed.
    private var providers: [String] {
        let names = [Budgets.claude, Budgets.copilot] + endpoints.endpoints.filter { !$0.isOnMac }.map(\.name)
        let removed = settings.budgets.providers.keys.filter { !names.contains($0) }.sorted()
        return names + removed
    }

    /// The Progetti with turns in the ledger or a Budget, by folder name.
    private var projects: [URL] {
        let folders = Set(ledger.entries.compactMap(\.project).map(\.standardizedFileURL))
            .union(settings.budgets.projects.keys.map { URL(filePath: $0, directoryHint: .isDirectory).standardizedFileURL })
        return folders.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// The page where the provider called `name` sets its own hard limit; `nil` when Bubo does not know one.
    static func limitsPage(of name: String, among endpoints: [OpenAICompatibleEndpoint]) -> URL? {
        if name == Budgets.claude { return URL(string: "https://platform.claude.com/settings/limits") }
        if name == Budgets.copilot { return URL(string: "https://github.com/settings/billing/budgets") }
        guard let endpoint = endpoints.first(where: { $0.name == name }) else { return nil }
        return switch endpoint.kind {
        case .openAI: URL(string: "https://platform.openai.com/settings/organization/limits")
        case .gemini: URL(string: "https://console.cloud.google.com/billing/budgets")
        case .openRouter: URL(string: "https://openrouter.ai/settings/keys")
        case .custom where endpoint.baseURL.host() == "api.x.ai": URL(string: "https://console.x.ai")
        case .custom, .ollama, .lmStudio: nil
        }
    }
}

#Preview {
    BudgetSettingsView()
        .environment(CostLedger())
        .frame(width: 480, height: 600)
}
