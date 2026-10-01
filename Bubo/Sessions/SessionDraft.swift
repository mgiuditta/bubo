import Foundation

/// A Sessione about to start from a Domanda: what is typed, and the Domanda it continues, if one was answered.
nonisolated struct SessionDraft: Equatable, Sendable {
    /// What the Sessione should do.
    var prompt = ""
    /// The Domanda the Sessione continues; empty when there is none.
    var question = ""
    /// What arrived of the Domanda's answer; empty when there is none.
    var answer = ""

    /// Whether the Sessione continues a Domanda that got an answer.
    var continuesQuestion: Bool { !answer.isEmpty }

    /// The Sessione's first prompt: the Domanda and its answer, if any, then `request`.
    func firstPrompt(_ request: String) -> String {
        guard continuesQuestion else { return request }
        let request = request.isEmpty ? String(localized: "Continua da qui, lavorando nel Progetto.") : request
        return String(localized: "Prima ti ho chiesto: \(question)\n\nMi hai risposto: \(answer)\n\n\(request)")
    }
}
