import Foundation
import Observation

/// The account shown in Settings › Account, refreshed from the `claude` CLI.
@Observable
final class AccountModel {
    /// The last state read from the CLI; `nil` until the first read ends.
    private(set) var state: AccountState?
    /// Whether a login started from Bubo is waiting for the browser.
    private(set) var isSigningIn = false
    /// Why the last login or logout failed, if it did.
    private(set) var failure: String?
    /// Whether an API key is in the keychain; `nil` until the first read ends.
    private(set) var hasAPIKey: Bool?
    /// Why the last API key operation failed, if it did. Never contains the key.
    private(set) var apiKeyFailure: String?

    private let cli: ClaudeCLI
    private let apiKeys: APIKeyStore

    /// Creates a model that talks to `cli` and keeps the API key in `apiKeys`.
    init(cli: ClaudeCLI = ClaudeCLI(), apiKeys: APIKeyStore = APIKeyStore()) {
        self.cli = cli
        self.apiKeys = apiKeys
    }

    /// Reads again whether an API key is saved, without reading the key.
    func refreshAPIKey() async {
        do {
            hasAPIKey = try await apiKeys.containsKey()
        } catch {
            apiKeyFailure = error.localizedDescription
        }
    }

    /// Saves `key` in the keychain, replacing any saved key.
    func saveAPIKey(_ key: String) async {
        do {
            try await apiKeys.save(key)
            apiKeyFailure = nil
        } catch {
            apiKeyFailure = error.localizedDescription
        }
        await refreshAPIKey()
    }

    /// Deletes the saved API key.
    func removeAPIKey() async {
        do {
            try await apiKeys.delete()
            apiKeyFailure = nil
        } catch {
            apiKeyFailure = error.localizedDescription
        }
        await refreshAPIKey()
    }

    /// Whether `ANTHROPIC_API_KEY` is in the user's environment, where `claude` in Terminal pays per use with it.
    private(set) var hasAPIKeyInEnvironment = false

    /// Looks for `ANTHROPIC_API_KEY` in Bubo's environment and in the login shell's, without reading it.
    ///
    /// Bubo never passes it on: `ChildEnvironment` builds the environment of `claude` from scratch.
    func refreshEnvironment() async {
        hasAPIKeyInEnvironment = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.isEmpty == false
        if !hasAPIKeyInEnvironment { hasAPIKeyInEnvironment = await cli.locator.loginShellHasAPIKey() }
    }

    /// Reads the state again from `claude auth status`.
    func refresh() async {
        state = await cli.status()
    }

    /// Runs `claude auth login` and refreshes when it ends; cancelling the task stops the login.
    func signIn() async {
        isSigningIn = true
        failure = nil
        defer { isSigningIn = false }
        do {
            try await cli.signIn()
        } catch where !Task.isCancelled {
            failure = error.localizedDescription
        } catch {}
        // The user stopped waiting for the browser: the account is as before, and this task can't run the CLI any more.
        guard !Task.isCancelled else { return }
        await refresh()
    }

    /// Runs `claude auth logout` and refreshes.
    func signOut() async {
        failure = nil
        do {
            try await cli.signOut()
        } catch {
            failure = error.localizedDescription
        }
        await refresh()
    }
}
