import Foundation

/// What `claude` reports about a conversation besides its answer: what it is doing, and a one-line summary.
nonisolated enum AgentProgress: Equatable, Sendable {
    /// What the conversation is doing, as `session_state_changed` says.
    enum State: String, Decodable, Sendable {
        /// `claude` works on the turn.
        case running
        /// `claude` waits for an answer to `canUseTool`: a permission or a question.
        case requiresAction = "requires_action"
        /// The turn is over and no subagent is left in the background.
        case idle
    }

    case state(State)
    /// The first line of the latest text of the main thread, at most 200 characters.
    case summary(String)
    /// A write the agent asked for in `file`, an absolute path: the lines it writes, trimmed, unique, at most 100.
    case edit(file: String, lines: [String])
    /// Files the agent read, absolute paths: one for `Read`, those `Grep` or `Glob` found, at most 100.
    case read(files: [String])
    /// The agent turned to what the Variante `nome` stands for: by its tag `⟦orb:nome⟧`, or by the tool it uses.
    ///
    /// The bridge sends only names of the rosa, or of its fallback; Bubo still looks each one up in the Catalogo.
    case variante(String)
    /// A Bash command of the agent ended, or went to the background: it may have started or stopped a server.
    case ranCommand
    /// The Sandbox stopped the Bash command that just ended from doing this.
    case sandboxBlock(SandboxBlock)
    /// The agent wrote in the Memoria di Progetto, or memories came into its turn: a line Ricordato or Richiamato.
    case memory(MemoryLine.Event)
    /// An action denied in a turn with nobody in front of it, for the report of the Esecuzione.
    case denial(BridgeDenial)
    /// The mode `claude` chose for a turn with nobody in front of it, from its `init`, such as `auto` or `default`:
    /// the Modalità autonoma may be unavailable for the model or the account.
    case permissionMode(String)
}
