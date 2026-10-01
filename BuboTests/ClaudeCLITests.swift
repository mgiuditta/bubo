import Foundation
import Synchronization
import Testing
@testable import Bubo

struct ClaudeCLITests {
    /// A fake `claude` on the login `PATH` that answers with fixed outputs and records its calls.
    final class FakeProcesses: Sendable {
        let calls = Mutex<[[String]]>([])
        let whichClaude: ProcessOutput
        let claude: ProcessOutput

        init(
            whichClaude: ProcessOutput = ProcessOutput(exitCode: 0, standardOutput: "zsh: no job control\n/Users/ada/.local/bin/claude\n"),
            claude: ProcessOutput = ProcessOutput(exitCode: 0, standardOutput: "")
        ) {
            self.whichClaude = whichClaude
            self.claude = claude
        }

        var runner: ProcessRunner {
            ProcessRunner { [self] executable, arguments in
                calls.withLock { $0.append([executable.path] + arguments) }
                return executable.lastPathComponent == "claude" ? claude : whichClaude
            }
        }

        func cli(isOnline: Bool = true) -> ClaudeCLI {
            ClaudeCLI(runner: runner, isOnline: { isOnline }, locator: .onlyLoginShell(runner))
        }
    }

    @Test func statusRunsAuthStatusOnTheClaudeFromTheLoginShell() async {
        let processes = FakeProcesses(claude: ProcessOutput(exitCode: 0, standardOutput: #"{"loggedIn": true, "email": "ada@example.com"}"#))
        let state = await processes.cli().status()
        #expect(state == .signedIn(email: "ada@example.com", plan: nil))
        #expect(processes.calls.withLock { $0 } == [
            ["/bin/zsh", "-l", "-i", "-c", "command -v claude"],
            ["/Users/ada/.local/bin/claude", "auth", "status", "--json"],
        ])
    }

    @Test func missingExecutableIsCLIMissing() async {
        let processes = FakeProcesses(whichClaude: ProcessOutput(exitCode: 1, standardOutput: ""))
        #expect(await processes.cli().status() == .cliMissing)
    }

    @Test func shellNoiseWithoutAPathIsCLIMissing() async {
        let processes = FakeProcesses(whichClaude: ProcessOutput(exitCode: 0, standardOutput: "claude not found\n"))
        #expect(await processes.cli().status() == .cliMissing)
    }

    @Test func offlineSkipsTheCLIAndNeverFallsBackToPaidOptions() async {
        let processes = FakeProcesses()
        #expect(await processes.cli(isOnline: false).status() == .offline)
        #expect(processes.calls.withLock { $0 }.count == 1)
    }

    @Test func failingRunnerIsAnUnknownError() async {
        let runner = ProcessRunner { executable, _ in
            guard executable.lastPathComponent == "claude" else {
                return ProcessOutput(exitCode: 0, standardOutput: "/usr/local/bin/claude")
            }
            throw CocoaError(.executableNotLoadable)
        }
        let cli = ClaudeCLI(runner: runner, isOnline: { true }, locator: .onlyLoginShell(runner))
        #expect(await cli.status() == .unknownError(exitCode: -1))
    }

    @Test func signOutRunsAuthLogout() async throws {
        let processes = FakeProcesses()
        try await processes.cli().signOut()
        #expect(processes.calls.withLock { $0.last } == ["/Users/ada/.local/bin/claude", "auth", "logout"])
    }

    @Test func signInThatFailsThrowsItsExitCode() async {
        let processes = FakeProcesses(claude: ProcessOutput(exitCode: 3, standardOutput: ""))
        await #expect(throws: ClaudeCLIError.failed(exitCode: 3)) {
            try await processes.cli().signIn()
        }
    }

    @Test func signInWithoutCLIThrowsCLIMissing() async {
        let processes = FakeProcesses(whichClaude: ProcessOutput(exitCode: 1, standardOutput: ""))
        await #expect(throws: ClaudeCLIError.cliMissing) {
            try await processes.cli().signIn()
        }
    }

    @Test func onlyAuthCommandsReachClaude() async throws {
        let processes = FakeProcesses(claude: ProcessOutput(exitCode: 0, standardOutput: #"{"loggedIn": true}"#))
        let cli = processes.cli()
        _ = await cli.status()
        try await cli.signIn()
        try await cli.signOut()
        let claudeCalls = processes.calls.withLock { $0 }.filter { $0[0].hasSuffix("/claude") }
        #expect(claudeCalls.map { Array($0.dropFirst()) } == [["auth", "status", "--json"], ["auth", "login"], ["auth", "logout"]])
    }

    @Test func liveRunnerCollectsOutputAndExitCode() async throws {
        let output = try await ProcessRunner.live.run(URL(filePath: "/bin/sh"), ["-c", "echo out; echo err >&2; exit 4"])
        #expect(output == ProcessOutput(exitCode: 4, standardOutput: "out\n", standardError: "err\n"))
    }
}
