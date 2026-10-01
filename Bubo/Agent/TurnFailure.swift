import Foundation

/// Why `claude` could not answer a turn, as the bridge reported it: the text, and the SDK's own reasons when it had
/// some (`bridge/src/failure.ts`).
nonisolated struct TurnFailure: Equatable, Sendable {
    /// What `claude` wrote, such as `API Error: 401 Invalid API key · Please run /login`.
    var message: String
    /// The SDK's code of the error, such as `billing_error` (`SDKAssistantMessageError`).
    var reason: String?
    /// The HTTP status of the last request `claude` retried, when the API answered one.
    var status: Int?
    /// Whether the last retry waited for the API's first byte in vain.
    var hadNoResponse = false
}
