import SwiftUI

/// A Domanda opened from the Conversazioni: its earlier turns, then the answer in course and the composer that
/// continues it (ADR 0013).
struct QuestionDetail: View {
    let question: ArchivedQuestion?
    @Bindable var model: QuestionModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                let title = question?.title ?? model.turns.first?.prompt
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let title {
                        Text(title)
                            .buboTitleStyle()
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { index, turn in
                        // The first prompt said again right under the same title is a doubled line.
                        PastTurn(turn: turn, showsPrompt: index > 0 || !Self.isSame(turn.prompt, as: title))
                    }
                }
                .frame(maxWidth: Spacing.readingWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(Spacing.l)
            }
            .defaultScrollAnchor(.bottom)
            QuestionView(model: model)
                .frame(maxWidth: Spacing.readingWidth)
            .padding(Spacing.l)
        }
        .onAppear {
            if let question { model.continueQuestion(question) }
        }
        .onChange(of: question?.id) {
            if let question { model.continueQuestion(question) }
        }
    }

    /// Whether `prompt` reads as `title`, apart from the spaces around them.
    private static func isSame(_ prompt: String, as title: String?) -> Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines) == title?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A turn already answered: what was asked, dimmer, then the answer.
private struct PastTurn: View {
    let turn: QuestionTurn
    /// Whether what was asked shows: not when the title above already says it.
    let showsPrompt: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if showsPrompt {
                Text(turn.prompt)
                    .font(.buboBody)
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
            }
            AnswerProse(prose: turn.answer)
                .font(.buboBody)
                .textSelection(.enabled)
        }
    }
}
