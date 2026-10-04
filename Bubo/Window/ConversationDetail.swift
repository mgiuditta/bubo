import SwiftUI

/// The conversation chosen in the sidebar: a Domanda, a Sessione or a conversation of the command line.
struct ConversationDetail: View {
    /// A ``ConversationItem/id``: `q-`, `s-` or `c-` before the item's own id.
    let id: String
    let questions: QuestionModel
    let sessions: SessionStore?

    var body: some View {
        let ownID = String(id.dropFirst(2))
        switch id.prefix(2) {
        case "q-":
            let archived = questions.archive?.questions.first { $0.id.uuidString == ownID }
            QuestionDetail(question: archived, model: questions)
        case "s-":
            if let sessions, let session = sessions.sessions.first(where: { $0.id.uuidString == ownID }) {
                SessionDetail(session: session, store: sessions)
            } else {
                missing
            }
        default:
            if let sessions {
                CLIDetail(conversationID: ownID, store: sessions)
            } else {
                missing
            }
        }
    }

    private var missing: some View {
        ContentUnavailableView("Conversazione non trovata", systemImage: "questionmark.bubble")
    }
}

/// A conversation of the command line, read only.
private struct CLIDetail: View {
    let conversationID: String
    let store: SessionStore
    @State private var reader: ConversationReader?

    var body: some View {
        Group {
            if let reader {
                ConversationReaderView(reader: reader)
            } else {
                LoadingLabel("Leggo la conversazione…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: conversationID) {
            let result = ConversationResult(id: conversationID, title: "", source: .cli, project: nil,
                                            conversation: conversationID, date: .now, best: nil)
            let reader = ConversationReader(result: result, words: [], resumeID: conversationID,
                                            read: { [store] in try await store.transcript(ofConversation: $0) },
                                            indexed: { _ in [] })
            await reader.load()
            self.reader = reader
        }
    }
}
