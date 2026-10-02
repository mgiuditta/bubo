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

    /// The error an endpoint answered with HTTP `status` and `body`.
    init(status: Int, body: String) {
        if status == 401 || status == 403 {
            self = .keyRefused
            return
        }
        struct Envelope: Decodable {
            struct Failure: Decodable { let message: String? }
            let error: Failure?
        }
        let message = (try? JSONDecoder().decode(Envelope.self, from: Data(body.utf8)))?.error?.message
        self = .failed(message ?? HTTPURLResponse.localizedString(forStatusCode: status))
    }
}
