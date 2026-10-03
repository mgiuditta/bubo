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
    /// A Budget the Domanda counts in is spent: it was not sent, or `claude` stopped at the cap. Nothing is asked again
    /// without the user's choice.
    case budgetExhausted(QuestionBudgetStop)
    /// No `copilot` with a paid plan answers a Domanda the user sent to Copilot (ADR 0011).
    case copilotUnavailable
    /// Copilot did not answer, saying why.
    case copilotFailed(String)
    /// Anything else, such as the Domande folder not being writable.
    case unexpected
}
