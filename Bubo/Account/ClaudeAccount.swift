import Network
import Observation

/// The user's Claude account, read and changed only through the `claude` CLI (ADR 0003).
@Observable
final class ClaudeAccount {
    /// The last status read; `nil` until the first read finishes.
    private(set) var status: AccountStatus?
    /// `true` while `claude auth login` or `claude auth logout` runs.
    private(set) var isBusy = false

    private let cli: ClaudeCLI
    private let isOnline: @Sendable () async -> Bool

    init(cli: ClaudeCLI = .live, isOnline: @escaping @Sendable () async -> Bool = ClaudeAccount.networkIsReachable) {
        self.cli = cli
        self.isOnline = isOnline
    }

    /// Reads `claude auth status` again.
    func refresh() async {
        status = await readStatus()
    }

    /// Starts the Anthropic login in the browser, then reads the status again.
    func logIn() async {
        await runThenRefresh(["auth", "login"])
    }

    /// Logs out of Claude Code, then reads the status again.
    func logOut() async {
        await runThenRefresh(["auth", "logout"])
    }

    private func runThenRefresh(_ arguments: [String]) async {
        isBusy = true
        defer { isBusy = false }
        // ponytail: failures show up in the status read right after, no separate error.
        _ = try? await cli.run(arguments)
        await refresh()
    }

    private func readStatus() async -> AccountStatus {
        let result: CommandResult
        do {
            result = try await cli.run(["auth", "status"])
        } catch ClaudeCLIError.binaryNotFound {
            return .cliMissing
        } catch {
            return .unknown(detail: error.localizedDescription)
        }
        let status = AccountStatus(authStatus: result)
        // Offline never falls back to the API key: it only says why Claude won't answer.
        if case .connected = status, await !isOnline() {
            return .offline
        }
        return status
    }

    /// Whether the Mac has a usable network path right now.
    @concurrent nonisolated static func networkIsReachable() async -> Bool {
        let monitor = NWPathMonitor()
        defer { monitor.cancel() }
        for await path in monitor {
            return path.status == .satisfied
        }
        return false
    }
}
