import Foundation

/// What went wrong with the credential or the network at the first turn, each with its remedy in the onboarding
/// (spec 26).
///
/// A credential exists, since `claude auth status` said so: only the first request tells whether it works. The kind
/// comes from the SDK's code and HTTP status first, and from the texts of `claude` only where the SDK has none.
nonisolated enum AuthFailure: Equatable, Sendable {
    /// The API key was refused: wrong, revoked, without credit or of a disabled organization.
    case invalidKey
    /// The login of `claude` expired or was revoked.
    case loginExpired
    /// `claude` has no credential at all.
    case signedOut
    /// The account cannot use Claude Code: its plan, its organization, or a hold on it.
    case accountWithoutClaudeCode
    /// The API could not be reached.
    case offline

    /// The failure `error` of a turn stands for, or `nil` when it is none of these.
    ///
    /// - Parameter usesAPIKey: Whether `claude` answers with an API key rather than a claude.ai login: the same refusal
    ///   means a key that does not work, or a login that does not.
    init?(_ error: any Error, usesAPIKey: Bool) {
        switch error {
        // The bridge sends `signInRequired` for the SDK's `authentication_failed`.
        case AgentBridgeError.signInRequired: self = usesAPIKey ? .invalidKey : .loginExpired
        case let AgentBridgeError.turnFailed(failure): self.init(failure, usesAPIKey: usesAPIKey)
        case let AgentBridgeError.failed(message): self.init(TurnFailure(message: message), usesAPIKey: usesAPIKey)
        default: return nil
        }
    }

    /// The failure `failure` stands for, or `nil` when it is none of these.
    init?(_ failure: TurnFailure, usesAPIKey: Bool) {
        let text = failure.message.lowercased()
        let refused: AuthFailure = usesAPIKey ? .invalidKey : .accountWithoutClaudeCode
        if text.contains("not logged in") {
            self = .signedOut
            return
        }
        switch failure.reason {
        case "authentication_failed": self = usesAPIKey || text.contains("invalid api key") ? .invalidKey : .loginExpired
        case "oauth_org_not_allowed", "account_on_hold", "verification_required": self = .accountWithoutClaudeCode
        case "billing_error": self = refused
        default:
            switch failure.status ?? Self.status(in: failure.message) {
            case 401: self = usesAPIKey ? .invalidKey : .loginExpired
            case 403: self = refused
            case 400 where text.contains("organization has been disabled") || text.contains("disabled organization"):
                self = refused
            default:
                if text.contains("login expired") || text.contains("oauth token revoked") {
                    self = .loginExpired
                } else if Self.connectionFailures.contains(where: text.contains) {
                    self = .offline
                } else {
                    return nil
                }
            }
        }
    }

    /// How `claude` words a request that never reached the API.
    private static let connectionFailures = [
        "unable to connect to api", "connection error", "connection to the api was lost", "connection dropped",
    ]

    /// The HTTP status in a text of `claude` such as `API Error: 403 …`.
    private static func status(in message: String) -> Int? {
        message.firstMatch(of: /API Error: (\d{3})\b/).flatMap { Int($0.1) }
    }
}
