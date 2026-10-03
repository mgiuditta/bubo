import SwiftUI

/// The Domanda field of the HUD and its streaming answer.
// ponytail: plain text answer; Markdown rendering comes with the HUD bubbles of phase 3.
struct QuestionView: View {
    @Bindable var model: QuestionModel
    @Environment(\.openURL) private var openURL
    @Environment(HUDPresenter.self) private var hud
    @State private var isPickingRetry = false
    /// The cloud endpoint picked in "Rifai con…" that waits for the user's consent before it receives anything.
    @State private var askingConsent: RetryAlternative?
    @State private var isAskingConsent = false
    /// The endpoint picked in "Rifai con…" whose Allegati wait for a confirmation, or cannot go to it.
    @State private var reviewedAlternative: RetryAlternative?
    /// What may go to that endpoint of the Allegati.
    @State private var attachmentVerdict: AttachmentPolicy.Verdict?
    /// Whether the model picked in "Rifai con…" becomes the preference of the Domanda's Tipo.
    @State private var alwaysUse = false
    /// Push-to-talk, whose partial text fills the prompt; `nil` in previews.
    @Environment(PushToTalk.self) private var voice: PushToTalk?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            // Dropped on the Orb before the HUD opened: they go with the next Domanda from here too.
            if !model.attachments.isEmpty {
                AttachmentChips(attachments: model.attachments, remove: model.detach)
            }
            SessionProposalButton(model: model, hud: hud)
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

            if let offer = model.localModelOffer {
                LocalModelInvitation(offer: offer, accept: model.acceptLocalModel,
                                     dismiss: model.dismissLocalModelOffer)
            }

            if model.invitesBetterVoice {
                BetterVoiceInvitation(dismiss: model.dismissBetterVoice)
            }

            if let reviewedAlternative, case let .endpoint(endpoint) = reviewedAlternative.target, let attachmentVerdict {
                attachmentReview(attachmentVerdict, endpoint: endpoint, alternative: reviewedAlternative)
            }

            if let resumesAt = model.resumesAt {
                HStack(spacing: Spacing.small) {
                    Text("Riprendo alle \(resumesAt, format: .dateTime.hour().minute()).")
                        .font(Typography.body(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                    Button("Annulla", action: model.stop)
                }
            } else if let failure = model.failure {
                QuestionNotice(failure: failure, model: model) { isPickingRetry = true }
            } else if model.isAnswering && model.answer.isEmpty {
                LoadingLabel("Chiedo a Claude…")
            } else if !model.answer.isEmpty {
                QuestionAnswer(model: model) { isPickingRetry = true }
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
                          usesAPIKey: model.usesAPIKey, type: model.lastType, alwaysUse: $alwaysUse, pick: pick)
                // The models of the Copilot plan, read when the user asks for the list: never in the background.
                .task { await model.readCopilotModels() }
        }
        // "Usa sempre per «Tipo»" starts off every time "Rifai con…" opens.
        .onChange(of: isPickingRetry) {
            if isPickingRetry { alwaysUse = false }
        }
        // Ollama or LM Studio found on the Mac: proposed once, the first time the HUD opens after.
        // Not in the app that hosts the tests: it shares the user's defaults, and the proposal is made only once.
        .task {
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            await model.lookForLocalModel()
        }
        // A new answer under way leaves the Allegati's question behind.
        .onChange(of: model.isAnswering) {
            if model.isAnswering { closeAttachmentReview() }
        }
        .confirmationDialog(consentTitle, isPresented: $isAskingConsent, presenting: askingConsent) { alternative in
            Button("Consenti e invia") {
                if case let .endpoint(endpoint) = alternative.target { model.endpoints.grantConsent(to: endpoint) }
                model.retry(with: alternative, alwaysUse: alwaysUse)
            }
            Button("Non ora", role: .cancel) {
                if case let .endpoint(endpoint) = alternative.target { model.decline(endpoint) }
            }
        } message: { alternative in
            if case let .endpoint(endpoint) = alternative.target {
                if model.askedAttachments.isEmpty {
                    Text("\(endpoint.name) riceve solo il testo della Domanda, mai file, modifiche o memoria dei Progetti, e la risposta si paga sulla tua chiave. Puoi revocare il consenso in Impostazioni › Modelli.")
                } else {
                    Text("\(endpoint.name) riceve il testo della Domanda e degli allegati che hai confermato, mai modifiche o memoria dei Progetti, e la risposta si paga sulla tua chiave. Puoi revocare il consenso in Impostazioni › Modelli.")
                }
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

    /// Asks again with `alternative`, once the Allegati of the Domanda may go to it; or shows why they cannot, or asks
    /// to confirm them.
    private func pick(_ alternative: RetryAlternative) {
        isPickingRetry = false
        closeAttachmentReview()
        guard case let .endpoint(endpoint) = alternative.target, !model.askedAttachments.isEmpty else {
            send(alternative)
            return
        }
        Task {
            let verdict = await model.attachmentVerdict(for: endpoint)
            if verdict == .allowed {
                send(alternative)
            } else {
                reviewedAlternative = alternative
                attachmentVerdict = verdict
            }
        }
    }

    /// Asks again with `alternative`, or first asks the user's consent when it is a cloud that never had it.
    private func send(_ alternative: RetryAlternative) {
        if model.needsConsent(for: alternative) {
            askingConsent = alternative
            isAskingConsent = true
        } else {
            model.retry(with: alternative, alwaysUse: alwaysUse)
        }
    }

    /// The confirmation of the Allegati about to go to `endpoint`, or why they cannot and the way to Claude.
    @ViewBuilder
    private func attachmentReview(_ verdict: AttachmentPolicy.Verdict, endpoint: OpenAICompatibleEndpoint,
                                  alternative: RetryAlternative) -> some View {
        switch verdict {
        case let .needsConfirmation(attachments):
            AttachmentConfirmation(attachments: attachments, endpoint: endpoint) {
                model.confirm(attachments, for: endpoint)
                closeAttachmentReview()
                send(alternative)
            } askClaude: {
                closeAttachmentReview()
                model.askClaude()
            } cancel: {
                closeAttachmentReview()
            }
        case let .overCap(tokens, cap):
            ErrorNotice("Allegati troppo lunghi per \(endpoint.name)",
                        remedy: "Circa \(tokens.formatted()) token, il massimo per questo modello è \(cap.formatted()). Bubo non li taglia: Claude li legge interi.",
                        actionTitle: "Chiedi a Claude", action: askClaudeInstead)
        case let .onlyClaude(allegato):
            ErrorNotice("«\(allegato.name)» va solo a Claude", remedy: Self.onlyClaudeReason(allegato.kind, endpoint: endpoint),
                        actionTitle: "Chiedi a Claude", action: askClaudeInstead)
        case .allowed:
            EmptyView()
        }
    }

    /// Why an Allegato of `kind` cannot go to `endpoint`.
    private static func onlyClaudeReason(_ kind: Allegato.Kind, endpoint: OpenAICompatibleEndpoint) -> LocalizedStringKey {
        switch kind {
        case .folder: "È una cartella: Claude la legge dal disco, \(endpoint.name) riceverebbe solo il suo nome."
        case .image: "È un'immagine: Claude la legge dal disco, \(endpoint.name) riceve solo testo."
        case .file, .text: "Bubo non ne legge il testo: Claude lo apre dal disco, \(endpoint.name) riceve solo testo."
        }
    }

    private func askClaudeInstead() {
        closeAttachmentReview()
        model.askClaude()
    }

    private func closeAttachmentReview() {
        reviewedAlternative = nil
        attachmentVerdict = nil
    }

    private var consentTitle: String {
        guard case let .endpoint(endpoint)? = askingConsent?.target else { return "" }
        return String(localized: "Mandare la Domanda a \(endpoint.name)?",
                      comment: "Consent asked the first time a Domanda would go to a cloud provider other than Claude.")
    }
}

#Preview {
    QuestionView(model: QuestionModel())
        .padding()
        .background(Palette.ink)
        .environment(HUDPresenter())
}
