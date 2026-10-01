/// Why a Domanda got no answer.
enum QuestionFailure: Error, Equatable {
    /// No `claude` on the user's `PATH`.
    case claudeMissing
    /// The agent bridge failed.
    case bridge(AgentBridgeError)
    /// The Mac has no network connection.
    case offline
    /// The user chose the API key, but none is saved.
    case apiKeyMissing
    /// Anything else, such as the Domande folder not being writable.
    case unexpected
}
