import Foundation

/// A Sessione about to start: what is typed, and the Domanda or the Cronologia CLI conversation it continues, if any.
nonisolated struct SessionDraft: Equatable, Sendable {
    /// What the Sessione should do.
    var prompt = ""
    /// The answered turns of the Domanda the Sessione continues, in order; empty when there is none.
    var turns: [QuestionTurn] = []
    /// The conversation the Sessione continues as a fork, if any: from the Cronologia CLI, or a Sessione's turn.
    var conversation: CLIConversation?
    /// The message of `conversation` the fork stops at, included: Continua da qui. `nil` for all of it.
    var upToMessage: String?
    /// The Progetto proposed by the Allegati of the Domanda; `nil` for the most recent one.
    var project: URL?
    /// The files of the Domanda's Allegati inside `project`, which the first prompt points to.
    var files: [URL] = []

    /// Whether the Sessione continues a Domanda that got an answer.
    var continuesQuestion: Bool { !turns.isEmpty }

    /// The first prompt of the Domanda the Sessione continues, which names it; empty when there is none.
    var question: String { turns.first?.prompt ?? "" }

    /// Whether the Sessione can start with nothing typed: it continues a Domanda or a conversation.
    var canStartEmpty: Bool { continuesQuestion || conversation != nil }

    /// The Sessione's first prompt: the Domanda's turns, if any, quoted as context and never as instructions (see
    /// ``QuestionTurn/transcript(_:then:)``), then `request`, the only instruction, then the paths of `files`, each
    /// on its own line with its control and separator characters escaped.
    ///
    /// It starts the Sessione like any other, through ``SessionStore/start(_:title:branch:in:onCheckout:forkingFrom:upTo:issue:choice:)``:
    /// the trust dialog first, then the Progetto's Sandbox and the Modalità manuale.
    ///
    /// Continuing a conversation, `claude` already has it: an empty `request` asks to go on from there.
    func firstPrompt(_ request: String) -> String {
        let prompt = promptWithoutFiles(request)
        guard let project, !files.isEmpty else { return prompt }
        let root = project.standardizedFileURL.pathComponents
        let paths = files.map { file in
            let components = file.standardizedFileURL.pathComponents
            let inside = components.starts(with: root) ? Array(components.dropFirst(root.count)) : components
            // A file name is anyone's text: on one line, it cannot add a line that passes for the user's request.
            return "- " + RepoActivations.escaped(inside.isEmpty ? "." : inside.joined(separator: "/"))
        }
        return String(localized: "\(prompt)\n\nFile del Progetto da guardare:\n\(paths.joined(separator: "\n"))",
                      comment: "First prompt of a Sessione from a Domanda's files: the request, then their paths in the Progetto, one per line")
    }

    /// The first prompt before the files of the Allegati.
    private func promptWithoutFiles(_ request: String) -> String {
        if conversation != nil {
            return request.isEmpty ? String(localized: "Continua da dove ti eri fermato.") : request
        }
        guard continuesQuestion else { return request }
        let request = request.isEmpty ? String(localized: "Continua da qui, lavorando nel Progetto.") : request
        return QuestionTurn.transcript(turns, then: request)
    }
}
