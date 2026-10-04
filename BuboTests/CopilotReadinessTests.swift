import Foundation
import Synchronization
import Testing
@testable import Bubo

struct CopilotReadinessTests {
    static let paid = #"{"quotaSnapshots":{"chat":{"isUnlimitedEntitlement":true},"completions":{"isUnlimitedEntitlement":true},"premium_interactions":{"isUnlimitedEntitlement":false}}}"#
    static let free = #"{"quotaSnapshots":{"chat":{"isUnlimitedEntitlement":false},"completions":{"isUnlimitedEntitlement":false}}}"#

    /// What a `copilot` server writes: the answers to ``CopilotReadiness/requests``, out of order as `copilot` sends them.
    static func answers(authenticated: Bool = true, quota: String? = paid) -> String {
        let auth = authenticated
            ? #"{"isAuthenticated":true,"authType":"user","host":"https://github.com","login":"ada"}"#
            : #"{"isAuthenticated":false,"statusMessage":"Not authenticated"}"#
        let quotaAnswer = quota.map { #"{"jsonrpc":"2.0","id":3,"result":\#($0)}"# }
            ?? #"{"jsonrpc":"2.0","id":3,"error":{"code":-32603,"message":"Not authenticated. Please authenticate first."}}"#
        return [#"{"jsonrpc":"2.0","id":1,"result":{"version":"1.0.91","protocolVersion":3}}"#,
                #"{"jsonrpc":"2.0","method":"session.lifecycle","params":{}}"#,
                quotaAnswer,
                #"{"jsonrpc":"2.0","id":2,"result":\#(auth)}"#]
            .map { String(decoding: RPCFrames.frame($0), as: UTF8.self) }
            .joined()
    }

    /// A `copilot` in Homebrew's folder that answers with `output` and records its calls.
    final class FakeCopilot: Sendable {
        let calls = Mutex<[[String]]>([])
        let output: String

        init(output: String = CopilotReadinessTests.answers()) {
            self.output = output
        }

        func detect(installed: Bool = true) async -> CopilotReadiness {
            let locator = CopilotLocator(home: URL(filePath: "/Users/ada"), isExecutable: { _ in installed },
                                         runner: ProcessRunner { _, _ in ProcessOutput(exitCode: 1, standardOutput: "") },
                                         shell: URL(filePath: "/bin/zsh"))
            return await CopilotReadiness.detect(locator: locator, runner: ProcessRunner { [self] copilot, arguments in
                calls.withLock { $0.append([copilot.path] + arguments) }
                return ProcessOutput(exitCode: 0, standardOutput: output)
            })
        }
    }

    @Test func signedInOnAPaidPlanIsReadyWithTheAccount() async {
        let copilot = FakeCopilot()
        #expect(await copilot.detect() == .ready(version: "1.0.91", account: "ada"))
        #expect(copilot.calls.withLock { $0 } == [
            ["/opt/homebrew/bin/copilot", "--headless", "--no-auto-update", "--stdio"],
        ])
    }

    @Test func limitedChatIsCopilotFree() async {
        let copilot = FakeCopilot(output: Self.answers(quota: Self.free))
        #expect(await copilot.detect() == .free(version: "1.0.91", account: "ada"))
    }

    @Test func anUnreadableQuotaCountsAsPaid() async {
        let copilot = FakeCopilot(output: Self.answers(quota: nil))
        #expect(await copilot.detect() == .ready(version: "1.0.91", account: "ada"))
    }

    @Test func noLoginIsSignedOut() async {
        let copilot = FakeCopilot(output: Self.answers(authenticated: false, quota: nil))
        #expect(await copilot.detect() == .signedOut(version: "1.0.91"))
    }

    @Test func noCopilotIsMissingAndRunsNothing() async {
        let copilot = FakeCopilot()
        #expect(await copilot.detect(installed: false) == .missing)
        #expect(copilot.calls.withLock { $0 }.isEmpty)
    }

    @Test func aCopilotThatDoesNotAnswerIsMissing() async {
        #expect(await FakeCopilot(output: "error: unknown option '--headless'\n").detect() == .missing)
    }

    @Test func aCopilotThatHangsIsMissing() async {
        let locator = CopilotLocator(isExecutable: { _ in true })
        let readiness = await CopilotReadiness.detect(locator: locator, runner: ProcessRunner { _, _ in
            try await Task.sleep(for: .seconds(60))
            return ProcessOutput(exitCode: 0, standardOutput: "")
        }, timeout: .milliseconds(50))
        #expect(readiness == .missing)
    }

    @Test func theRequestsAskNothingThatReturnsAToken() {
        let requests = String(decoding: CopilotReadiness.requests, as: UTF8.self)
        #expect(CopilotReadiness.methods == ["status.get", "auth.getStatus", "account.getQuota"])
        for method in CopilotReadiness.methods { #expect(requests.contains(#""method":"\#(method)""#)) }
        #expect(!requests.contains("getCurrentAuth"))
        #expect(!requests.contains("getAllUsers"))
        #expect(RPCFrames.answers(in: CopilotReadiness.requests).isEmpty)
    }

    @Test func theLocatorLooksOnlyForTheExecutable() async {
        let looked = Mutex<[String]>([])
        let locator = CopilotLocator(home: URL(filePath: "/Users/ada"), isExecutable: { url in
            looked.withLock { $0.append(url.path) }
            return false
        }, runner: ProcessRunner { _, _ in ProcessOutput(exitCode: 1, standardOutput: "") })
        #expect(await locator.executableURL() == nil)
        #expect(looked.withLock { $0 } == ["/opt/homebrew/bin/copilot", "/usr/local/bin/copilot",
                                          "/Users/ada/.local/bin/copilot", "/Users/ada/.npm-global/bin/copilot"])
    }

    @Test func theLoginShellFindsAnotherCopilot() async {
        let locator = CopilotLocator(isExecutable: { _ in false }, runner: ProcessRunner { _, arguments in
            #expect(arguments == ["-l", "-i", "-c", "command -v copilot"])
            return ProcessOutput(exitCode: 0, standardOutput: "Benvenuto\n/Users/ada/bin/copilot\n")
        })
        #expect(await locator.executableURL() == URL(filePath: "/Users/ada/bin/copilot"))
    }

    /// A real process, a fake `copilot`: it gets the requests on its standard input and no GitHub token in its
    /// environment, and Bubo reads its answers.
    @Test func aFakeCopilotGetsTheRequestsAndNoToken() async throws {
        let folder = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "copilot-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copilot = folder.appending(path: "copilot")
        try Data(Self.answers().utf8).write(to: folder.appending(path: "answers"))
        try Data("""
            #!/bin/sh
            cd "$(dirname "$0")"
            env > environment
            cat > requests
            cat answers
            """.utf8).write(to: copilot)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copilot.path)

        let base = ["HOME": "/Users/ada", "USER": "ada", "GH_TOKEN": "gho_leaked", "GITHUB_TOKEN": "ghp_leaked",
                    "COPILOT_GITHUB_TOKEN": "github_pat_leaked"]
        let runner = ProcessRunner.disclaimed(environment: ChildEnvironment.makeForCopilot(copilot: copilot, base: base),
                                              input: CopilotReadiness.requests)
        let locator = CopilotLocator(isExecutable: { _ in false }, runner: ProcessRunner { _, _ in
            ProcessOutput(exitCode: 0, standardOutput: copilot.path + "\n")
        })
        let readiness = await CopilotReadiness.detect(locator: locator, runner: runner)
        #expect(readiness == .ready(version: "1.0.91", account: "ada"))
        #expect(try Data(contentsOf: folder.appending(path: "requests")) == CopilotReadiness.requests)
        let environment = try String(contentsOf: folder.appending(path: "environment"), encoding: .utf8)
        #expect(!environment.contains("TOKEN"))
        #expect(!environment.contains("leaked"))
    }

    @Test func theRemediesNameTheCommands() {
        #expect(RemedyCommand.installCopilot.hasSuffix("brew install copilot-cli"))
        #expect(RemedyCommand.loginCopilot(URL(filePath: "/opt/homebrew/bin/copilot")) == "/opt/homebrew/bin/copilot login")
    }
}
