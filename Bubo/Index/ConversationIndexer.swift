import Foundation
import os

/// Brings the past conversations into the Indice: each turn of a Sessione when it ends, and the Cronologia CLI.
///
/// The messages come from the bridge, which reads them with the SDK (`getSessionMessages`), never from the transcript files.
/// They stay on the Mac: nothing of them goes to the network.
struct ConversationIndexer {
    /// The Indice the conversations go into.
    let index: SearchIndex
    /// The bridge that reads the conversations.
    let bridge: () async throws -> AgentBridge

    /// Puts the conversation `id`, which ran in `folder`, in the Indice, in place of what it had of it.
    ///
    /// - Parameter modified: When the conversation last changed; the date of the messages the SDK gives none.
    func add(_ id: String, in folder: URL?, modified: Date = .now) async {
        do {
            let messages = try await bridge().transcript(of: id, isComplete: true)
            try await index.store(messages, ofConversation: id, in: folder, modified: modified)
        } catch {
            Logger.index.error("Conversation not indexed: \(String(describing: error), privacy: .private)")
        }
    }

    /// Puts in the Indice the conversations it is missing: the turns of the Sessioni, as after the Indice was deleted,
    /// and the Cronologia CLI not indexed yet or changed since.
    ///
    /// - Parameters:
    ///   - turns: The conversation of each turn of the Sessioni, with the Progetto it ran in.
    ///   - history: The Cronologia CLI.
    func catchUp(turns: [(id: String, project: URL)], history: [CLIConversation]) async {
        for turn in turns where await index.modificationDate(ofConversation: turn.id) == nil {
            guard !Task.isCancelled else { return }
            await add(turn.id, in: turn.project)
        }
        for conversation in history {
            guard !Task.isCancelled else { return }
            if let indexed = await index.modificationDate(ofConversation: conversation.id),
               indexed >= conversation.lastModified { continue }
            await add(conversation.id, in: conversation.folder, modified: conversation.lastModified)
        }
    }

    /// Removes the conversations `ids` from the Indice.
    func forget(_ ids: [String]) async {
        do {
            try await index.forgetConversations(ids)
        } catch {
            Logger.index.error("Conversations not forgotten by the Indice: \(error)")
        }
    }
}
