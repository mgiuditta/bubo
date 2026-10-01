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
    /// A Bash command of the agent ended, or went to the background: it may have started or stopped a server.
    case ranCommand
    /// The Sandbox stopped the Bash command that just ended from doing this.
    case sandboxBlock(SandboxBlock)
}
