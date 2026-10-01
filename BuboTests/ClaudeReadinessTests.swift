import Foundation
import Synchronization
import Testing
@testable import Bubo

struct ClaudeReadinessTests {
    /// A `claude` in `~/.local/bin` that answers with recorded outputs and records its calls.
    final class FakeClaude: Sendable {
        let calls = Mutex<[[String]]>([])
        let version: ProcessOutput
        let status: ProcessOutput

        init(version: String = "2.1.286 (Claude Code)\n", status: ProcessOutput = ProcessOutput(exitCode: 0, standardOutput: #"""
            {"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty", "subscriptionType": "max"}
            """#)) {
            self.version = ProcessOutput(exitCode: 0, standardOutput: version)
            self.status = status
        }

        func detect(installed: Bool = true) async -> ClaudeReadiness {
            let locator = ClaudeLocator(home: URL(filePath: "/Users/ada"), isExecutable: { _ in installed },
                                        runner: ProcessRunner { _, _ in ProcessOutput(exitCode: 1, standardOutput: "") },
                                        shell: URL(filePath: "/bin/zsh"))
            return await ClaudeReadiness.detect(locator: locator, runner: ProcessRunner { [self] claude, arguments in
                calls.withLock { $0.append([claude.path] + arguments) }
                return arguments == ["--version"] ? version : status
            })
        }
    }

    @Test func signedInWithASubscriptionIsReadyWithThePlan() async {
        let claude = FakeClaude()
        #expect(await claude.detect() == .ready(version: "2.1.286", method: "Max"))
        #expect(claude.calls.withLock { $0 } == [
            ["/Users/ada/.local/bin/claude", "--version"],
            ["/Users/ada/.local/bin/claude", "auth", "status", "--json"],
        ])
    }

    @Test func signedInWithAnAPIKeyIsReadyWithAPIKey() async {
        let claude = FakeClaude(status: ProcessOutput(exitCode: 0, standardOutput: #"{"loggedIn": true, "authMethod": "api_key", "apiKeySource": "ANTHROPIC_API_KEY"}"#))
        #expect(await claude.detect() == .ready(version: "2.1.286", method: "API key"))
    }

    @Test func noCredentialIsSignedOut() async {
        let claude = FakeClaude(status: ProcessOutput(exitCode: 1, standardOutput: #"{"loggedIn": false, "authMethod": "none"}"#))
        #expect(await claude.detect() == .signedOut(version: "2.1.286"))
    }

    @Test func unreadableStatusIsSignedOut() async {
        let claude = FakeClaude(status: ProcessOutput(exitCode: 0, standardOutput: "Not logged in · Please run /login"))
        #expect(await claude.detect() == .signedOut(version: "2.1.286"))
    }

    @Test func versionBelowTheMinimumIsOutdatedWithoutAskingTheLogin() async {
        let claude = FakeClaude(version: "2.0.77 (Claude Code)\n")
        #expect(await claude.detect() == .outdated(version: "2.0.77"))
        #expect(claude.calls.withLock { $0 }.count == 1)
    }

    @Test func noClaudeIsMissingAndRunsNothing() async {
        let claude = FakeClaude()
        #expect(await claude.detect(installed: false) == .missing)
        #expect(claude.calls.withLock { $0 }.isEmpty)
    }

    @Test func aClaudeThatDoesNotRunIsMissing() async {
        let locator = ClaudeLocator(home: URL(filePath: "/Users/ada"), isExecutable: { _ in true })
        let readiness = await ClaudeReadiness.detect(locator: locator, runner: ProcessRunner { _, _ in
            throw CocoaError(.executableNotLoadable)
        })
        #expect(readiness == .missing)
    }
}
