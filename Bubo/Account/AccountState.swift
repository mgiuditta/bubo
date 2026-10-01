import Foundation

/// The user's Claude account as the `claude` CLI reports it.
///
/// Built only from `claude auth status`: Bubo never reads, copies or stores
/// tokens (ADR 0003).
enum AccountState: Equatable, Sendable {
    /// Signed in; `plan` is the subscription, when the CLI reports one.
    case signedIn(email: String?, plan: String?)
    /// No login in the CLI.
    case signedOut
    /// The CLI's login has expired and needs a new sign-in.
    case expired
    /// No `claude` executable on the user's login `PATH`.
    case cliMissing
    /// The Mac has no network connection.
    case offline
    /// The CLI answered in a way Bubo does not understand.
    case unknownError(exitCode: Int32)
}

extension AccountState {
    /// Creates the state from the output of `claude auth status --json`.
    init(statusOutput output: ProcessOutput) {
        let status = try? JSONDecoder().decode(AuthStatus.self, from: Data(output.standardOutput.utf8))
        let message = status == nil ? output.standardOutput + output.standardError : output.standardError
        if message.localizedCaseInsensitiveContains("expired") {
            self = .expired
            return
        }
        switch (status?.loggedIn, output.exitCode) {
        case (true, 0):
            self = .signedIn(email: status?.email, plan: status?.subscriptionType?.capitalized)
        case (false, _):
            self = .signedOut
        default:
            self = .unknownError(exitCode: output.exitCode)
        }
    }
}

/// The fields of `claude auth status --json` that Bubo shows. No token is among them.
nonisolated struct AuthStatus: Decodable {
    var loggedIn: Bool
    var email: String?
    var subscriptionType: String?
    /// `claude.ai` for a subscription, `api_key` for a key, as `claude` reports it.
    var authMethod: String?
}
