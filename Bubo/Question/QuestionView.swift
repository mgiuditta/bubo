import SwiftUI

/// The Domanda field of the HUD and its streaming answer.
// ponytail: plain text answer; Markdown rendering comes with the HUD bubbles of phase 3.
struct QuestionView: View {
    @Bindable var model: QuestionModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL
    @Environment(HUDPresenter.self) private var hud
    @State private var isPickingRetry = false
    /// The cloud endpoint picked in "Rifai con…" that waits for the user's consent before it receives anything.
    @State private var askingConsent: RetryAlternative?
    @State private var isAskingConsent = false
    /// Push-to-talk, whose partial text fills the prompt; `nil` in previews.
    @Environment(PushToTalk.self) private var voice: PushToTalk?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(spacing: Spacing.xSmall) {
                TextField(voice?.isListening == true ? "Ti ascolto…" : "Chiedi qualcosa a Claude", text: $model.prompt)
                    .textFieldStyle(.plain)
                    .font(Typography.body(size: 15))
                    .onSubmit(model.ask)
                    // On macOS the title is only a placeholder, so VoiceOver would find a nameless field.
                    .accessibilityLabel("Chiedi qualcosa a Claude")
                    .accessibilityIdentifier("question.prompt")
                    .onKeyPress(phases: .down, action: chipKeyPress)
                // The Domanda ↔ Sessione switch: the conversation so far goes with it.
                Button("Trasforma in Sessione", systemImage: "arrow.triangle.branch") {
                    hud.createSession(from: model.turnIntoSession())
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
                .help("Trasforma in Sessione")
                .accessibilityIdentifier("question.turnIntoSession")
                if model.isAnswering {
                    Button("Ferma", systemImage: "stop.fill", action: model.stop)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.textSecondary)
                        .help("Ferma la risposta")
                }
            }
            .padding(Spacing.small)
            .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(Palette.line)
            }

            if showsChip, let route = model.chipRoute {
                RouterChip(route: route)
                    .accessibilityAction(named: "Modello successivo") { model.chooseModel(forward: true) }
                    .accessibilityAction(named: "Sforzo più alto") { model.chooseEffort(stronger: true) }
                    .accessibilityAction(named: "Sforzo più basso") { model.chooseEffort(stronger: false) }
                    .accessibilityAction(named: "Torna al router") { model.returnToRouter() }
            }

            if let voice, let failure = voice.failure {
                VoiceNotice(failure: failure, dismiss: voice.dismissFailure)
            }

            // The Sintesi parlata as subtitles, while Bubo says it.
            if let subtitle = model.subtitle {
                Text(verbatim: subtitle)
                    .font(Typography.body(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("question.subtitle")
            }

            if model.invitesBetterVoice {
                BetterVoiceInvitation(dismiss: model.dismissBetterVoice)
            }

            if let resumesAt = model.resumesAt {
                HStack(spacing: Spacing.small) {
                    Text("Riprendo alle \(resumesAt, format: .dateTime.hour().minute()).")
                        .font(Typography.body(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                    Button("Annulla", action: model.stop)
                }
            } else if let failure = model.failure {
                notice(for: failure)
            } else if model.isAnswering && model.answer.isEmpty {
                LoadingLabel("Chiedo a Claude…")
            } else if !model.answer.isEmpty {
                ScrollView {
                    Text(verbatim: model.answer)
                        .font(Typography.body(size: 14))
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .defaultScrollAnchor(.bottom)
                .accessibilityLabel("Risposta di Claude")
                .accessibilityIdentifier("question.answer")
                // Under every answer, once it is complete or stopped: who answered it, why, and at what cost.
                if !model.isAnswering, let routedAnswer = model.routedAnswer {
                    HStack(spacing: Spacing.xSmall) {
                        RouterLine(answer: routedAnswer)
                        // ⌘↑ only with the prompt empty: while typing it stays the text field's "go to the start".
                        Button("Rifai più forte", systemImage: "arrow.up", action: model.retryStronger)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.textSecondary)
                            .keyboardShortcut(.upArrow, modifiers: .command)
                            .disabled(model.strongerRoute == nil || !model.prompt.isEmpty)
                            .help("Rifai con un modello o uno sforzo più forte (⌘↑)")
                            .accessibilityIdentifier("question.retryStronger")
                        Button("Rifai con…", systemImage: "arrow.triangle.swap") { isPickingRetry = true }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.textSecondary)
                            .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                            .disabled(model.retryAlternatives.isEmpty && model.excludedEndpoints.isEmpty
                                      || !model.prompt.isEmpty)
                            .help("Rifai con un altro modello (⌘⇧↑)")
                            .accessibilityIdentifier("question.retryWith")
                    }
                }
            }

            if let savedNote = model.savedNote {
                HStack(spacing: Spacing.small) {
                    Label("Ricordato in \(savedNote.deletingPathExtension().lastPathComponent)",
                          systemImage: "bookmark")
                        .font(Typography.body(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                    Button("Apri la nota") { openURL(savedNote) }
                        .accessibilityIdentifier("question.openNote")
                }
            }
        }
        // On the whole field, not on the button: a failed answer offers "Rifai con…" too, without the reason line.
        .popover(isPresented: $isPickingRetry, arrowEdge: .bottom) {
            RetryWithList(alternatives: model.retryAlternatives, excluded: model.excludedEndpoints,
                          usesAPIKey: model.usesAPIKey, pick: pick)
        }
        .confirmationDialog(consentTitle, isPresented: $isAskingConsent, presenting: askingConsent) { alternative in
            Button("Consenti e invia") {
                if case let .endpoint(endpoint) = alternative.target { model.endpoints.grantConsent(to: endpoint) }
                model.retry(with: alternative)
            }
            Button("Non ora", role: .cancel) {
                if case let .endpoint(endpoint) = alternative.target { model.decline(endpoint) }
            }
        } message: { alternative in
            if case let .endpoint(endpoint) = alternative.target {
                Text("\(endpoint.name) riceve solo il testo della Domanda, mai file, modifiche o memoria dei Progetti, e la risposta si paga sulla tua chiave. Puoi revocare il consenso in Impostazioni › Modelli.")
            }
        }
    }

    /// Whether the chip shows: there is a prompt, and push-to-talk is not held, which sends at release.
    private var showsChip: Bool {
        !model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && voice?.isListening != true
    }

    /// The chip's keys in the prompt: Tab and ⇧Tab the model, ⌥↑ and ⌥↓ the effort, Esc back to the router; any
    /// other key, or one with nothing to change, keeps its usual meaning.
    private func chipKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard showsChip else { return .ignored }
        switch press.key {
        case .tab:
            model.chooseModel(forward: !press.modifiers.contains(.shift))
            return .handled
        // AppKit delivers ⇧Tab as the back-tab character.
        case KeyEquivalent("\u{19}"):
            model.chooseModel(forward: false)
            return .handled
        case .upArrow where press.modifiers.contains(.option):
            return model.chooseEffort(stronger: true) ? .handled : .ignored
        case .downArrow where press.modifiers.contains(.option):
            return model.chooseEffort(stronger: false) ? .handled : .ignored
        case .escape:
            return model.returnToRouter() ? .handled : .ignored
        default:
            return .ignored
        }
    }

    /// Asks again with `alternative`, or first asks the user's consent when it is a cloud that never had it.
    private func pick(_ alternative: RetryAlternative) {
        isPickingRetry = false
        if model.needsConsent(for: alternative) {
            askingConsent = alternative
            isAskingConsent = true
        } else {
            model.retry(with: alternative)
        }
    }

    private var consentTitle: String {
        guard case let .endpoint(endpoint)? = askingConsent?.target else { return "" }
        return String(localized: "Mandare la Domanda a \(endpoint.name)?",
                      comment: "Consent asked the first time a Domanda would go to a cloud provider other than Claude.")
    }

    @ViewBuilder
    private func notice(for failure: QuestionFailure) -> some View {
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
            ErrorNotice("Il modello non ha risposto", remedy: "\(message)", actionTitle: "Rifai con…") { isPickingRetry = true }
        case .unreachable:
            ErrorNotice("Il server non risponde", remedy: "Controlla che sia acceso e che l'indirizzo sia giusto.",
                        actionTitle: "Rifai con…") { isPickingRetry = true }
        case .unexpectedResponse:
            ErrorNotice("Risposta non riconosciuta", remedy: "Il server non parla il formato di OpenAI Chat Completions.",
                        actionTitle: "Rifai con…") { isPickingRetry = true }
        }
    }
}

#Preview {
    QuestionView(model: QuestionModel())
        .padding()
        .background(Palette.ink)
        .environment(HUDPresenter())
}
