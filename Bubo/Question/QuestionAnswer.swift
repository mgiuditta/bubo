import SwiftUI

/// The Domanda's answer as it streams, scrolling to its end, with the reason line once it is complete: the same in the
/// HUD and in the Panel's bubble.
struct QuestionAnswer: View {
    let model: QuestionModel
    /// Opens "Rifai con…".
    let pickRetry: () -> Void

    var body: some View {
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
                Button("Rifai con…", systemImage: "arrow.triangle.swap") { pickRetry() }
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
}
