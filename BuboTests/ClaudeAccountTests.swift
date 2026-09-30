import Testing
@testable import Bubo

struct ClaudeAccountTests {
    nonisolated static let connectedJSON = """
        {"loggedIn": true, "authMethod": "claude.ai", "email": "ada@example.com", "orgName": "Ada", "subscriptionType": "max"}
        """
    nonisolated static let consoleJSON = """
        {"loggedIn": true, "authMethod": "console", "email": "ada@example.com"}
        """
    nonisolated static let notConnectedJSON = """
        {"loggedIn": false, "authMethod": "none", "apiProvider": "firstParty"}
        """

    private func account(returning result: CommandResult, online: Bool = true) -> ClaudeAccount {
        ClaudeAccount(cli: ClaudeCLI { _ in result }, isOnline: { online })
    }

    @Test func connectedShowsEmailAndPlan() async {
        let account = account(returning: CommandResult(exitCode: 0, standardOutput: Self.connectedJSON))
        await account.refresh()
        #expect(account.status == .connected(email: "ada@example.com", plan: "max"))
    }

    @Test func consoleLoginHasNoPlan() async {
        let account = account(returning: CommandResult(exitCode: 0, standardOutput: Self.consoleJSON))
        await account.refresh()
        #expect(account.status == .connected(email: "ada@example.com", plan: nil))
    }

    @Test func loggedOutIsNotConnected() async {
        let account = account(returning: CommandResult(exitCode: 1, standardOutput: Self.notConnectedJSON))
        await account.refresh()
        #expect(account.status == .notConnected)
    }

    @Test func expiredLoginIsExpired() async {
        let result = CommandResult(exitCode: 1, standardOutput: Self.notConnectedJSON, standardError: "Login expired · Please run /login")
        let account = account(returning: result)
        await account.refresh()
        #expect(account.status == .expired)
    }

    @Test func missingBinaryIsCLIMissing() async {
        let account = ClaudeAccount(cli: ClaudeCLI { _ in throw ClaudeCLIError.binaryNotFound }, isOnline: { true })
        await account.refresh()
        #expect(account.status == .cliMissing)
    }

    @Test(arguments: [
        CommandResult(exitCode: 2, standardOutput: "", standardError: "boom"),
        CommandResult(exitCode: 1, standardOutput: connectedJSON),
        CommandResult(exitCode: 0, standardOutput: notConnectedJSON),
    ])
    func unexpectedExitCodeIsUnknown(result: CommandResult) async {
        let account = account(returning: result)
        await account.refresh()
        #expect(account.status == .unknown(detail: result.standardError.isEmpty ? "exit \(result.exitCode)" : result.standardError))
    }

    @Test(arguments: ["not json", "[]", #"{"loggedIn": true}"#, #"{"loggedIn": "yes"}"#])
    func unexpectedJSONIsUnknown(output: String) async {
        let account = account(returning: CommandResult(exitCode: 0, standardOutput: output))
        await account.refresh()
        #expect(account.status == .unknown(detail: "exit 0"))
    }

    @Test func connectedWithoutNetworkIsOfflineNotAPIKey() async {
        let account = account(returning: CommandResult(exitCode: 0, standardOutput: Self.connectedJSON), online: false)
        await account.refresh()
        #expect(account.status == .offline)
    }

    @Test func logInRunsLoginThenRefreshes() async {
        let calls = Calls()
        let account = ClaudeAccount(
            cli: ClaudeCLI { arguments in
                await calls.append(arguments)
                return CommandResult(exitCode: 0, standardOutput: Self.connectedJSON)
            },
            isOnline: { true }
        )
        await account.logIn()
        #expect(await calls.list == [["auth", "login"], ["auth", "status"]])
        #expect(account.status == .connected(email: "ada@example.com", plan: "max"))
        #expect(account.isBusy == false)
    }

    @Test func logOutRunsLogoutThenRefreshes() async {
        let calls = Calls()
        let account = ClaudeAccount(
            cli: ClaudeCLI { arguments in
                await calls.append(arguments)
                return CommandResult(exitCode: 1, standardOutput: Self.notConnectedJSON)
            },
            isOnline: { true }
        )
        await account.logOut()
        #expect(await calls.list == [["auth", "logout"], ["auth", "status"]])
        #expect(account.status == .notConnected)
    }
}

/// Records the arguments of each `claude` run.
private actor Calls {
    private(set) var list: [[String]] = []

    func append(_ arguments: [String]) {
        list.append(arguments)
    }
}
