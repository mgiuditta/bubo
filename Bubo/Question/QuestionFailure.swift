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
    /// The OpenAI-compatible endpoint picked in "Rifai con…" did not answer, or could not be asked.
    case endpoint(OpenAICompatibleError)
    /// The Allegati could not go to the endpoint picked in "Rifai con…": unconfirmed, over its cap, or without text.
    /// Nothing was sent.
    case attachmentsHeld
    /// Anything else, such as the Domande folder not being writable.
    case unexpected
}
