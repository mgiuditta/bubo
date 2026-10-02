import Foundation

/// What a model reads to summarize a Sessione: its title, Progetto and branch, and the messages of all its turns.
///
/// Only what the user and the agent wrote: the bridge's transcripts carry no output of the tools.
nonisolated struct SummaryInput: Equatable, Sendable {
    /// The Sessione summarized, for the cost of the summary.
    var session: UUID
    var title: String
    /// The Progetto's name.
    var projectName: String
    /// The Sessione's branch; `nil` outside git or on the checkout.
    var branch: String?
    /// The messages of every turn, oldest first.
    var messages: [CLIConversation.Message]

    /// The most characters a single message keeps: a long answer leaves room to the other turns.
    static let messageLimit = 2_000

    /// The input with the latest messages that fit in `characterLimit`, each cut to ``messageLimit``; the first ones
    /// are left out.
    func trimmed(toCharacters characterLimit: Int) -> SummaryInput {
        var kept: [CLIConversation.Message] = []
        var length = 0
        for message in messages.reversed() {
            let text = String(message.text.prefix(Self.messageLimit))
            guard length + text.count <= characterLimit else { break }
            length += text.count
            kept.append(CLIConversation.Message(id: message.id, isFromUser: message.isFromUser, text: text,
                                                date: message.date))
        }
        var input = self
        input.messages = kept.reversed()
        return input
    }

    /// The input with every secret `filter` finds replaced, in the title and in the messages.
    func redacted(by filter: SecretFilter) -> SummaryInput {
        var input = self
        input.title = filter.redacting(title)
        input.messages = messages.map {
            CLIConversation.Message(id: $0.id, isFromUser: $0.isFromUser, text: filter.redacting($0.text), date: $0.date)
        }
        return input
    }

    /// The Sessione as the model reads it: its title, Progetto and branch, then the conversation.
    var transcript: String {
        let header = ["Titolo: \(title)", "Progetto: \(projectName)", branch.map { "Branch: \($0)" }]
            .compactMap(\.self).joined(separator: "\n")
        let lines = messages.map { "[\($0.isFromUser ? "Utente" : "Agente")] \($0.text)" }
        return header + "\n\nConversazione:\n" + lines.joined(separator: "\n\n")
    }

    /// What the model is asked, in the language of the note.
    static let instructions = """
        Riassumi in italiano questa Sessione di lavoro di un agente di programmazione. Rispondi solo con tre sezioni \
        Markdown, in quest'ordine: "## Fatto", "## Decisioni", "## Aperto", ognuna con al più 5 punti elenco brevi. \
        Al massimo 200 parole in tutto. Niente introduzione né conclusione. Non riportare chiavi, token, password né \
        altri segreti.
        """

    /// The whole prompt for Claude: the instructions, then the Sessione.
    var prompt: String {
        Self.instructions + "\n\n" + transcript
    }
}
