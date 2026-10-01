import Foundation
import Synchronization
import Testing
@testable import Bubo

extension ClaudeLocator {
    /// A locator that finds no `claude` on disk and asks the login shell through `runner`.
    static func onlyLoginShell(_ runner: ProcessRunner) -> ClaudeLocator {
        ClaudeLocator(home: URL(filePath: "/Users/ada"), isExecutable: { _ in false }, runner: runner,
                      shell: URL(filePath: "/bin/zsh"))
    }
}

struct ClaudeLocatorTests {
    /// A file system with only `executables`, and a login shell; both record what they are asked.
    final class FakeMac: Sendable {
        let checked = Mutex<[String]>([])
        let shellCalls = Mutex<[[String]]>([])
        let executables: Set<String>
        let shellOutput: ProcessOutput
        let shellDelay: Duration

        init(executables: Set<String> = [],
             shellOutput: ProcessOutput = ProcessOutput(exitCode: 1, standardOutput: ""),
             shellDelay: Duration = .zero) {
            self.executables = executables
            self.shellOutput = shellOutput
            self.shellDelay = shellDelay
        }

        var locator: ClaudeLocator {
            ClaudeLocator(
                home: URL(filePath: "/Users/ada"),
                isExecutable: { [self] url in
                    checked.withLock { $0.append(url.path) }
                    return executables.contains(url.path)
                },
                runner: ProcessRunner { [self] executable, arguments in
                    shellCalls.withLock { $0.append([executable.path] + arguments) }
                    try await Task.sleep(for: shellDelay)
                    return shellOutput
                },
                shell: URL(filePath: "/bin/zsh"),
                shellTimeout: .milliseconds(50)
            )
        }
    }

    nonisolated static let channels = [
        "/Users/ada/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/Users/ada/.npm-global/bin/claude",
        "/Users/ada/.claude/local/claude",
    ]

    @Test(arguments: channels)
    func eachChannelIsFoundWithoutTheShell(path: String) async {
        let mac = FakeMac(executables: [path])
        #expect(await mac.locator.executableURL()?.path == path)
        #expect(mac.shellCalls.withLock { $0 }.isEmpty)
    }

    @Test func severalChannelsAreAllListedAndTheFirstWins() async {
        let mac = FakeMac(executables: ["/usr/local/bin/claude", "/Users/ada/.local/bin/claude"])
        let installations = await mac.locator.installations()
        #expect(installations.map(\.path) == ["/Users/ada/.local/bin/claude", "/usr/local/bin/claude"])
    }

    @Test func onlyTheChannelsAreChecked() async {
        let mac = FakeMac()
        _ = await mac.locator.installations()
        // Never the app's PATH, never a credential file.
        #expect(mac.checked.withLock { $0 } == Self.channels)
    }

    @Test func withNoChannelTheLoginShellFindsClaude() async {
        let mac = FakeMac(shellOutput: ProcessOutput(exitCode: 0, standardOutput: "zsh: no job control\n/Users/ada/.bun/bin/claude\n"))
        #expect(await mac.locator.executableURL()?.path == "/Users/ada/.bun/bin/claude")
        #expect(mac.shellCalls.withLock { $0 } == [["/bin/zsh", "-l", "-i", "-c", "command -v claude"]])
    }

    @Test func withNoChannelAndNoClaudeOnTheLoginPathThereIsNone() async {
        let mac = FakeMac()
        #expect(await mac.locator.installations().isEmpty)
    }

    @Test func shellNoiseWithoutAPathIsNone() async {
        let mac = FakeMac(shellOutput: ProcessOutput(exitCode: 0, standardOutput: "claude not found\n"))
        #expect(await mac.locator.executableURL() == nil)
    }

    @Test func aStalledLoginShellTimesOut() async {
        let mac = FakeMac(shellOutput: ProcessOutput(exitCode: 0, standardOutput: "/Users/ada/.bun/bin/claude\n"),
                          shellDelay: .seconds(60))
        let started = ContinuousClock.now
        #expect(await mac.locator.executableURL() == nil)
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}
