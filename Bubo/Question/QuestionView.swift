import SwiftUI

/// The Domanda field of the HUD and its streaming answer.
// ponytail: plain text answer; Markdown rendering comes with the HUD bubbles of phase 3.
struct QuestionView: View {
    @Bindable var model: QuestionModel

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

            if let failure = model.failure {
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
        case .bridge(.bridgeExited), .bridge(.spawnFailed), .unexpected:
            ErrorNotice("Il collegamento con Claude si è interrotto", remedy: "Riprova: Bubo lo riavvia.",
                        actionTitle: "Riprova", action: model.retry)
        case .bridge(.unsupportedVersion):
            ErrorNotice("Il collegamento con Claude non è aggiornato", remedy: "Reinstalla Bubo, poi riprova.",
                        actionTitle: "Riprova", action: model.retry)
        }
    }
}

#Preview {
    QuestionView(model: QuestionModel())
        .padding()
        .background(Palette.ink)
}
