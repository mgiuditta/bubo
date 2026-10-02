import SwiftUI

/// Why the last Domanda got no answer, with the way out: the same in the HUD and in the Panel's bubble.
struct QuestionNotice: View {
    /// The failure to explain.
    let failure: QuestionFailure
    let model: QuestionModel
    /// Opens "Rifai con…".
    let pickRetry: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        switch failure {
        case .claudeMissing:
            ErrorNotice("Claude Code non trovato", remedy: "Installa la CLI claude, poi riprova.",
                        actionTitle: "Riprova", action: model.retry)
        case .bridge(.failed(let message)):
            ErrorNotice("Claude non ha risposto", remedy: "\(message)", actionTitle: "Riprova", action: model.retry)
        case .bridge(.turnFailed(let failure)):
            ErrorNotice("Claude non ha risposto", remedy: "\(failure.message)", actionTitle: "Riprova", action: model.retry)
        // A Domanda never runs in the Sandbox: `sandboxUnavailable` cannot reach it.
        case .bridge(.bridgeExited), .bridge(.spawnFailed), .bridge(.sandboxUnavailable), .unexpected:
            ErrorNotice("Il collegamento con Claude si è interrotto", remedy: "Riprova: Bubo lo riavvia.",
                        actionTitle: "Riprova", action: model.retry)
        case .bridge(.unsupportedVersion):
            ErrorNotice("Il collegamento con Claude non è aggiornato", remedy: "Reinstalla Bubo, poi riprova.",
                        actionTitle: "Riprova", action: model.retry)
        case .bridge(.claudeOutdated):
            ErrorNotice("Aggiorna Claude Code", remedy: "Questa versione è troppo vecchia per Bubo. Aggiornala nel Terminale, poi riprova.",
                        actionTitle: "Riprova", action: model.retry)
        case .bridge(.limitReached(let limit)):
            LimitNotice(limit: limit, resume: model.resumeAfterReset,
                        switchModel: { model.retry(model: limit.otherModel) },
                        useAPIKey: { Task { await model.useAPIKey() } })
        case .bridge(.signInRequired):
            ErrorNotice("L'accesso a Claude è scaduto", remedy: "Accedi di nuovo in Impostazioni › Account.",
                        actionTitle: "Apri Impostazioni") { openSettings() }
        case .offline:
            ErrorNotice("Sei offline", remedy: "Bubo non passa da solo alla API key: riprova quando torna la rete.",
                        actionTitle: "Riprova", action: model.retry)
        case .endpoint(let error):
            endpointNotice(for: error)
        case .attachmentsHeld:
            ErrorNotice("Allegati non inviati", remedy: "Non sono partiti: conferma ogni allegato, o chiedi a Claude.",
                        actionTitle: "Chiedi a Claude", action: model.askClaude)
        case .apiKeyMissing:
            ErrorNotice("Nessuna API key salvata", remedy: "Aggiungila in Impostazioni › Account, poi riprova.",
                        actionTitle: "Apri Impostazioni") { openSettings() }
        }
    }

    @ViewBuilder
    private func endpointNotice(for error: OpenAICompatibleError) -> some View {
        switch error {
        case .consentMissing:
            ErrorNotice("Domanda non inviata", remedy: "Serve il tuo consenso per mandarla a quel fornitore.",
                        actionTitle: "Apri Impostazioni") { openSettings() }
        case .billingUnconfirmed:
            ErrorNotice("Domanda non inviata a Gemini",
                        remedy: "Conferma in Impostazioni › Modelli che il progetto della chiave ha la fatturazione attiva: senza, Google usa le Domande per addestrare i suoi modelli e in Europa non è ammesso.",
                        actionTitle: "Apri Impostazioni") { openSettings() }
        case .modelMissing:
            ErrorNotice("Manca il modello", remedy: "Scrivi quale modello usare in Impostazioni › Modelli.",
                        actionTitle: "Apri Impostazioni") { openSettings() }
        case .keyMissing:
            ErrorNotice("Manca la chiave", remedy: "Aggiungila in Impostazioni › Modelli, poi riprova.",
                        actionTitle: "Apri Impostazioni") { openSettings() }
        case .keyRefused:
            ErrorNotice("Chiave rifiutata", remedy: "Il fornitore non l'ha accettata: controllala in Impostazioni › Modelli.",
                        actionTitle: "Apri Impostazioni") { openSettings() }
        case .failed(let message):
            ErrorNotice("Il modello non ha risposto", remedy: "\(message)", actionTitle: "Rifai con…") { pickRetry() }
        case .unreachable:
            ErrorNotice("Il server non risponde", remedy: "Controlla che sia acceso e che l'indirizzo sia giusto.",
                        actionTitle: "Rifai con…") { pickRetry() }
        case .unexpectedResponse:
            ErrorNotice("Risposta non riconosciuta", remedy: "Il server non parla il formato di OpenAI Chat Completions.",
                        actionTitle: "Rifai con…") { pickRetry() }
        case .providerLimit(.keyLimit):
            ErrorNotice("Limite della chiave raggiunto",
                        remedy: "La chiave di OpenRouter ha raggiunto il limite di spesa che le hai dato su openrouter.ai.",
                        actionTitle: "Rifai con…") { pickRetry() }
        case .providerLimit(.credits):
            ErrorNotice("Crediti OpenRouter finiti", remedy: "Ricarica i crediti su openrouter.ai, poi riprova.",
                        actionTitle: "Rifai con…") { pickRetry() }
        case .providerLimit(.inFlightBudget):
            ErrorNotice("Limite della chiave quasi raggiunto",
                        remedy: "Le richieste in corso su OpenRouter riempiono già il limite della chiave: riprova quando finiscono.",
                        actionTitle: "Rifai con…") { pickRetry() }
        }
    }
}
