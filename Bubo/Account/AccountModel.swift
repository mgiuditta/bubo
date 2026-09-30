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

    private let cli: ClaudeCLI

    /// Creates a model that talks to `cli`.
    init(cli: ClaudeCLI = ClaudeCLI()) {
        self.cli = cli
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
        } catch is CancellationError {
            // The user stopped waiting for the browser.
        } catch {
            failure = error.localizedDescription
        }
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
