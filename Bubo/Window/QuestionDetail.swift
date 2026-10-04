import SwiftUI

/// A Domanda opened from the Conversazioni: its earlier turns, then the answer in course and the composer that
/// continues it (ADR 0013).
struct QuestionDetail: View {
    let question: ArchivedQuestion?
    @Bindable var model: QuestionModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let title = question?.title ?? model.turns.first?.prompt {
                        Text(title)
                            .buboTitleStyle()
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { _, turn in
                        PastTurn(turn: turn)
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
}

/// A turn already answered: what was asked, dimmer, then the answer.
private struct PastTurn: View {
    let turn: QuestionTurn

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(turn.prompt)
                .font(.buboBody)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
            AnswerProse(prose: turn.answer)
                .font(.buboBody)
                .textSelection(.enabled)
        }
    }
}
