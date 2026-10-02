import Foundation
import Testing
@testable import Bubo

/// Samples of the failures of a first turn. The plain texts are the ones the `claude` 2.1.286 bundled with the SDK
/// 0.3.286 writes, read in its binary; the JSON bodies follow the shape of the API's errors; reasons and statuses follow
/// `SDKAssistantMessageError` and `api_retry` in `sdk.d.ts`. No turn of `claude` ran to make them.
struct AuthFailureTests {
    @Test(arguments: [
        // authentication_failed: the bridge sends `signInRequired`.
        (AgentBridgeError.signInRequired, false, AuthFailure.loginExpired),
        (AgentBridgeError.signInRequired, true, AuthFailure.invalidKey),
        (AgentBridgeError.failed(message: "Login expired · Please run /login"), false, AuthFailure.loginExpired),
        (AgentBridgeError.failed(message: "OAuth token revoked · Please run /login"), false, AuthFailure.loginExpired),
        (AgentBridgeError.failed(message: "Not logged in · Please run /login"), false, AuthFailure.signedOut),
        (AgentBridgeError.turnFailed(TurnFailure(message: "Invalid API key · Fix external API key",
                                                 reason: "authentication_failed")), false, AuthFailure.invalidKey),
        (AgentBridgeError.turnFailed(TurnFailure(message: "Credit balance is too low", reason: "billing_error")),
         true, AuthFailure.invalidKey),
        (AgentBridgeError.turnFailed(TurnFailure(message: "Credit balance is too low", reason: "billing_error")),
         false, AuthFailure.accountWithoutClaudeCode),
        (AgentBridgeError.turnFailed(TurnFailure(
            message: "API Error: 403 OAuth authentication is currently not allowed for this organization.",
            reason: "oauth_org_not_allowed")), false, AuthFailure.accountWithoutClaudeCode),
        (AgentBridgeError.turnFailed(TurnFailure(message: "API Error: account on hold", reason: "account_on_hold")),
         false, AuthFailure.accountWithoutClaudeCode),
        (AgentBridgeError.turnFailed(TurnFailure(message: "organization verification required",
                                                 reason: "verification_required")),
         false, AuthFailure.accountWithoutClaudeCode),
    ])
    func refusedCredentials(error: AgentBridgeError, usesAPIKey: Bool, failure: AuthFailure) {
        #expect(AuthFailure(error, usesAPIKey: usesAPIKey) == failure)
    }

    /// The HTTP statuses the SDK has no code of its own for: `claude` writes them as `API Error: <status> …`.
    @Test(arguments: [
        (#"API Error: 401 {"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#,
         true, AuthFailure.invalidKey),
        (#"API Error: 401 {"type":"error","error":{"type":"authentication_error","message":"OAuth token has expired."}}"#,
         false, AuthFailure.loginExpired),
        (#"API Error: 403 {"type":"error","error":{"type":"permission_error","message":"Request not allowed"}}"#,
         false, AuthFailure.accountWithoutClaudeCode),
        (#"API Error: 403 {"type":"error","error":{"type":"permission_error","message":"Request not allowed"}}"#,
         true, AuthFailure.invalidKey),
        (#"API Error: 400 {"type":"error","error":{"type":"invalid_request_error","message":"This organization has been disabled."}}"#,
         false, AuthFailure.accountWithoutClaudeCode),
    ])
    func refusedRequests(message: String, usesAPIKey: Bool, failure: AuthFailure) {
        let error = AgentBridgeError.turnFailed(TurnFailure(message: message, reason: "unknown"))
        #expect(AuthFailure(error, usesAPIKey: usesAPIKey) == failure)
    }

    @Test(arguments: [
        "API Error: Unable to connect to API. Check your internet connection",
        "API Error: Connection to the API was lost (ECONNRESET). This is usually temporary — try again.",
        "API Error: Connection error.",
    ])
    func noNetworkIsOffline(message: String) {
        let error = AgentBridgeError.turnFailed(TurnFailure(message: message, reason: "unknown"))
        #expect(AuthFailure(error, usesAPIKey: false) == .offline)
    }

    @Test func theStatusOfTheLastRetryCountsWithoutText() {
        let failure = TurnFailure(message: "boh", reason: "unknown", status: 401)
        #expect(AuthFailure(failure, usesAPIKey: true) == .invalidKey)
    }

    @Test(arguments: [
        AgentBridgeError.turnFailed(TurnFailure(message: "API Error: 529 Overloaded", reason: "overloaded", status: 529)),
        AgentBridgeError.turnFailed(TurnFailure(message: "API Error: 429 rate limited", reason: "rate_limit", status: 429)),
        AgentBridgeError.failed(message: "Claude Code process exited with code 1"),
        AgentBridgeError.limitReached(Quota.Limit()),
        AgentBridgeError.bridgeExited(status: 1),
    ])
    func otherFailuresHaveNoRemedyOfTheirOwn(error: AgentBridgeError) {
        #expect(AuthFailure(error, usesAPIKey: false) == nil)
    }
}
