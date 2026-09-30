import Foundation

/// The state of the user's Claude account, as reported by `claude auth status`.
enum AccountStatus: Equatable, Sendable {
    /// Logged in; `plan` is the subscription (`max`, `pro`…) or `nil` for Console and API key logins.
    case connected(email: String, plan: String?)
    case notConnected
    case expired
    case cliMissing
    case offline
    /// Anything Bubo can't read: a crash, an unexpected exit code or JSON it doesn't know.
    case unknown(detail: String)

    /// Creates the status from the result of `claude auth status` (JSON on stdout, exit 0 or 1).
    init(authStatus result: CommandResult) {
        let output = result.standardOutput + result.standardError
        // ponytail: the JSON has no expiry field; "expired" in the output is the only signal. Switch to a field if the CLI adds one.
        if output.localizedCaseInsensitiveContains("expired") {
            self = .expired
            return
        }
        guard let data = result.standardOutput.data(using: .utf8),
              let status = try? JSONDecoder().decode(AuthStatusPayload.self, from: data)
        else {
            self = .unknown(detail: Self.detail(of: result))
            return
        }
        switch (result.exitCode, status.loggedIn) {
        case (0, true):
            guard let email = status.email, !email.isEmpty else {
                self = .unknown(detail: Self.detail(of: result))
                return
            }
            self = .connected(email: email, plan: status.subscriptionType)
        case (1, false):
            self = .notConnected
        default:
            self = .unknown(detail: Self.detail(of: result))
        }
    }

    private static func detail(of result: CommandResult) -> String {
        let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "exit \(result.exitCode)" : message
    }
}

/// The keys Bubo reads from `claude auth status`. Tokens are never part of it.
private struct AuthStatusPayload: Decodable {
    let loggedIn: Bool
    let email: String?
    let subscriptionType: String?
}
