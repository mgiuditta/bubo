import Foundation

/// Why an OpenAI-compatible endpoint did not answer a Domanda. Never carries the key.
nonisolated enum OpenAICompatibleError: Error, Equatable, Sendable {
    /// A cloud that is not Claude, without the user's consent: nothing was sent.
    case consentMissing
    /// Gemini without the user's word that billing is on: nothing was sent.
    case billingUnconfirmed
    /// No model id written for the endpoint: nothing was sent.
    case modelMissing
    /// No key saved for an endpoint that needs one: nothing was sent.
    case keyMissing
    /// The endpoint refused the key.
    case keyRefused
    /// The endpoint answered with an error, in its words.
    case failed(String)
    /// The endpoint could not be reached, such as a local server that is off.
    case unreachable(URLError.Code)
    /// The endpoint answered something that is not Chat Completions.
    case unexpectedResponse
    /// The provider's own limit stopped the Domanda (OpenRouter's 402): Bubo shows that one, not a Budget of its own.
    case providerLimit(ProviderLimit)

    /// Which of OpenRouter's limits answered 402, from its `error.metadata.limit_source`.
    enum ProviderLimit: String, Sendable {
        /// The spending limit the user set on the key.
        case keyLimit = "openrouter_key_limit"
        /// The account's credits ran out.
        case credits = "openrouter_credits"
        /// The requests in progress would take the key past its limit.
        case inFlightBudget = "openrouter_in_flight_budget"
    }

    /// The error an endpoint answered with HTTP `status` and `body`.
    init(status: Int, body: String) {
        if status == 401 || status == 403 {
            self = .keyRefused
            return
        }
        struct Envelope: Decodable {
            struct Failure: Decodable {
                struct Metadata: Decodable {
                    let limitSource: String?
                    private enum CodingKeys: String, CodingKey { case limitSource = "limit_source" }
                }
                let message: String?
                let metadata: Metadata?
            }
            let error: Failure?
        }
        let failure = (try? JSONDecoder().decode(Envelope.self, from: Data(body.utf8)))?.error
        if status == 402, let limit = failure?.metadata?.limitSource.flatMap(ProviderLimit.init(rawValue:)) {
            self = .providerLimit(limit)
            return
        }
        let message = failure?.message
        self = .failed(message ?? HTTPURLResponse.localizedString(forStatusCode: status))
    }
}
