import Foundation

/// A Sessione about to start: what is typed, and the Domanda or the Cronologia CLI conversation it continues, if any.
nonisolated struct SessionDraft: Equatable, Sendable {
    /// What the Sessione should do.
    var prompt = ""
    /// The Domanda the Sessione continues; empty when there is none.
    var question = ""
    /// What arrived of the Domanda's answer; empty when there is none.
    var answer = ""
    /// The Cronologia CLI conversation the Sessione continues as a fork, if any.
    var conversation: CLIConversation?

    /// Whether the Sessione continues a Domanda that got an answer.
    var continuesQuestion: Bool { !answer.isEmpty }

    /// Whether the Sessione can start with nothing typed: it continues a Domanda or a conversation.
    var canStartEmpty: Bool { continuesQuestion || conversation != nil }

    /// The Sessione's first prompt: the Domanda and its answer, if any, then `request`.
    ///
    /// Continuing a conversation, `claude` already has it: an empty `request` asks to go on from there.
    func firstPrompt(_ request: String) -> String {
        if conversation != nil {
            return request.isEmpty ? String(localized: "Continua da dove ti eri fermato.") : request
        }
        guard continuesQuestion else { return request }
        let request = request.isEmpty ? String(localized: "Continua da qui, lavorando nel Progetto.") : request
        return String(localized: "Prima ti ho chiesto: \(question)\n\nMi hai risposto: \(answer)\n\n\(request)")
    }
}
