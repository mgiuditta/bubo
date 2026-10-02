import Foundation
import os

/// Riprendi (⌥↩) and Continua da qui (⌘↩) on a past conversation, from the Palette or the Cronologia window (spec 14).
final class ResumeActions {
    /// What Riprendi does with a conversation.
    nonisolated enum Resumption: Equatable, Sendable {
        /// The open Sessione: brought to the front, with its interrupted turn asked again; never a second `claude`.
        case bringToFront(UUID)
        /// The Archiviata Sessione: Aperta again in a new worktree, resuming its conversation.
        case reopen(UUID)
        /// A Cronologia CLI conversation: a new Sessione that forks all of it, waiting for its prompt.
        case startSession(SessionDraft)
    }

    private let sessions: () -> SessionStore?
    private let hud: HUDPresenter

    /// Creates the actions on the Sessioni of `sessions`, shown in `hud`.
    init(sessions: @escaping () -> SessionStore?, hud: HUDPresenter) {
        self.sessions = sessions
        self.hud = hud
    }

    /// What Riprendi does with `result` among `sessions`; `nil` when it cannot: the Sessione is gone, or Fusa while
    /// Fondi can still be undone.
    static func resumption(of result: ConversationResult, among sessions: [Session]) -> Resumption? {
        guard result.source == .session else {
            return .startSession(draft(continuing: result, upTo: nil))
        }
        guard let session = sessions.first(where: { $0.id.uuidString == result.id }) else { return nil }
        if session.isLive { return .bringToFront(session.id) }
        return session.phase == .archiviata ? .reopen(session.id) : nil
    }

    /// The new Sessione that continues `result` as a fork, up to `message` included; all of it when `nil`.
    static func draft(continuing result: ConversationResult, upTo message: String?) -> SessionDraft {
        let conversation = CLIConversation(id: result.conversation, title: result.title, folder: result.project,
                                           branch: nil, lastModified: result.date)
        return SessionDraft(conversation: conversation, upToMessage: message)
    }

    /// Whether Riprendi can act on `result`.
    func canResume(_ result: ConversationResult) -> Bool {
        Self.resumption(of: result, among: sessions()?.sessions ?? []) != nil
    }

    /// Riprendi: the same Sessione of Bubo, or a new one that forks the Cronologia CLI conversation.
    func resume(_ result: ConversationResult) {
        guard let store = sessions(),
              let resumption = Self.resumption(of: result, among: store.sessions)
        else { return }
        switch resumption {
        case let .bringToFront(id):
            store.resume(id)
            hud.show()
        case let .reopen(id):
            do {
                try store.reopen(id, prompt: String(localized: "Continua da dove ti eri fermato."))
            } catch {
                Logger.history.error("Sessione not reopened: \(String(describing: error), privacy: .public)")
            }
            hud.show()
        case let .startSession(draft):
            hud.createSession(from: draft)
        }
    }

    /// Continua da qui: a new Sessione in the conversation's Progetto, in a new worktree, that forks `result` up to
    /// `message` included, waiting for its prompt.
    func continueFrom(_ result: ConversationResult, upTo message: String?) {
        hud.createSession(from: Self.draft(continuing: result, upTo: message))
    }
}
