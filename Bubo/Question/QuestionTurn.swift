import Foundation

/// A turn of a Domanda: what the user asked and what arrived of the answer.
nonisolated struct QuestionTurn: Equatable, Sendable {
    /// What the user asked.
    var prompt: String
    /// What arrived of the answer.
    var answer: String

    /// Returns `request` after `turns`, so the model answering it knows what was asked and answered before.
    static func transcript(_ turns: [QuestionTurn], then request: String) -> String {
        let earlier = turns.map { turn in
            String(localized: "Prima ti ho chiesto: \(turn.prompt)\n\nMi hai risposto: \(turn.answer)",
                   comment: "A previous turn of a Domanda, sent to the model as context: what the user asked, then what the model answered")
        }
        return (earlier + [request]).joined(separator: "\n\n")
    }
}
