import Foundation

/// A Sessione about to start: what is typed, and the Domanda or the Cronologia CLI conversation it continues, if any.
nonisolated struct SessionDraft: Equatable, Sendable {
    /// What the Sessione should do.
    var prompt = ""
    /// The Domanda the Sessione continues; empty when there is none.
    var question = ""
    /// What arrived of the Domanda's answer; empty when there is none.
    var answer = ""
    /// The conversation the Sessione continues as a fork, if any: from the Cronologia CLI, or a Sessione's turn.
    var conversation: CLIConversation?
    /// The message of `conversation` the fork stops at, included: Continua da qui. `nil` for all of it.
    var upToMessage: String?
    /// The Progetto proposed by the Allegati of the Domanda; `nil` for the most recent one.
    var project: URL?
    /// The files of the Domanda's Allegati inside `project`, which the first prompt points to.
    var files: [URL] = []

    /// Whether the Sessione continues a Domanda that got an answer.
    var continuesQuestion: Bool { !answer.isEmpty }

    /// Whether the Sessione can start with nothing typed: it continues a Domanda or a conversation.
    var canStartEmpty: Bool { continuesQuestion || conversation != nil }

    /// The Sessione's first prompt: the Domanda and its answer, if any, then `request`.
    ///
    /// Continuing a conversation, `claude` already has it: an empty `request` asks to go on from there.
    func firstPrompt(_ request: String) -> String {
        let prompt = promptWithoutFiles(request)
        guard let project, !files.isEmpty else { return prompt }
        let root = project.standardizedFileURL.pathComponents
        let paths = files.map { file in
            let components = file.standardizedFileURL.pathComponents
            let inside = components.starts(with: root) ? Array(components.dropFirst(root.count)) : components
            return "- " + (inside.isEmpty ? "." : inside.joined(separator: "/"))
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
        return String(localized: "Prima ti ho chiesto: \(question)\n\nMi hai risposto: \(answer)\n\n\(request)")
    }
}
