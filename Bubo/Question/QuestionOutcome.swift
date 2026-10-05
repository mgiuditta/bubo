import SwiftUI

/// The answer to the last prompt of a Domanda: its wait, its failure or what arrived of it, then the note it saved.
/// The same in the card under the field and among the messages of a chat.
struct QuestionOutcome: View {
    let model: QuestionModel
    /// Whether it sits among the messages of a chat: the answer grows with the chat, and the wait shows as dots.
    var isInChat = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let resumesAt = model.resumesAt {
                HStack(spacing: Spacing.s) {
                    Text("Riprendo alle \(resumesAt, format: .dateTime.hour().minute()).")
                        .font(.buboInterface)
                        .foregroundStyle(Palette.textSecondary)
                    Button("Annulla", action: model.stop)
                }
            } else if let failure = model.failure {
                QuestionNotice(failure: failure, model: model, pickRetry: pickRetry)
            } else if model.isAnswering && model.answer.isEmpty {
                if isInChat {
                    ThinkingDots()
                } else {
                    LoadingLabel("Sto pensando…")
                }
            } else if !model.answer.isEmpty {
                QuestionAnswer(model: model, pickRetry: pickRetry, maxAnswerHeight: isInChat ? nil : 220)
            }
            if let savedChange = model.savedChange {
                SavedNoteLine(change: savedChange, undo: model.undoSavedChange)
            }
        }
    }

    private func pickRetry() {
        model.isPickingRetry = true
    }
}
