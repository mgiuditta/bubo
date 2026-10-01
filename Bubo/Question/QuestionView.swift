import SwiftUI

/// The Domanda field of the HUD and its streaming answer.
// ponytail: plain text answer; Markdown rendering comes with the HUD bubbles of phase 3.
struct QuestionView: View {
    @Bindable var model: QuestionModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL
    @Environment(HUDPresenter.self) private var hud

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(spacing: Spacing.xSmall) {
                TextField("Chiedi qualcosa a Claude", text: $model.prompt)
                    .textFieldStyle(.plain)
                    .font(Typography.body(size: 15))
                    .onSubmit(model.ask)
                    // On macOS the title is only a placeholder, so VoiceOver would find a nameless field.
                    .accessibilityLabel("Chiedi qualcosa a Claude")
                    .accessibilityIdentifier("question.prompt")
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
        case .apiKeyMissing:
            ErrorNotice("Nessuna API key salvata", remedy: "Aggiungila in Impostazioni › Account, poi riprova.",
                        actionTitle: "Apri Impostazioni") { openSettings() }
        }
    }
}

#Preview {
    QuestionView(model: QuestionModel())
        .padding()
        .background(Palette.ink)
        .environment(HUDPresenter())
}
