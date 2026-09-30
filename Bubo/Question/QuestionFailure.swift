/// Why a Domanda got no answer.
enum QuestionFailure: Error, Equatable {
    /// No `claude` on the user's `PATH`.
    case claudeMissing
    /// The agent bridge failed.
    case bridge(AgentBridgeError)
    /// Anything else, such as the Domande folder not being writable.
    case unexpected
}
