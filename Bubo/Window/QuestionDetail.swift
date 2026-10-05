import SwiftUI

/// A Domanda as a chat (ADR 0013): the Orb over it, its turns in order with the newest at the bottom, and the field
/// that continues it under them. The home shows it too, once its Domanda has started.
struct QuestionDetail: View {
    let question: ArchivedQuestion?
    @Bindable var model: QuestionModel

    var body: some View {
        VStack(spacing: 0) {
            ChatOrb()
                .overlay(alignment: .topTrailing) {
                    Button("Nuova Domanda", systemImage: "square.and.pencil", action: model.startNewQuestion)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.textSecondary)
                        // The whole square answers the click, not only the glyph.
                        .padding(Spacing.s)
                        .contentShape(.rect)
                        .help("Nuova Domanda")
                        .accessibilityIdentifier("question.close")
                }
                .frame(maxWidth: Spacing.readingWidth)
                .padding(.top, Spacing.m)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.l) {
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { _, turn in
                        UserBubble(text: turn.prompt)
                            .chatEntrance()
                        AnswerProse(prose: turn.answer)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Bubo")
                            .chatEntrance()
                    }
                    if !model.lastPrompt.isEmpty {
                        UserBubble(text: model.lastPrompt)
                            .chatEntrance()
                    }
                    QuestionOutcome(model: model, isInChat: true)
                        .chatEntrance()
                    QuestionRequests(model: model)
                        .chatEntrance()
                }
                .animation(Motion.standard, value: model.turns.count)
                .animation(Motion.standard, value: model.lastPrompt)
                .animation(Motion.standard, value: model.answer.isEmpty)
                .frame(maxWidth: Spacing.readingWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(Spacing.l)
            }
            // A chat opens on its last message, and follows the answer as it grows.
            .defaultScrollAnchor(.bottom)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            QuestionView(model: model, showsOutcome: false)
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
