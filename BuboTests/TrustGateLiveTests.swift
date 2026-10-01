import Foundation
import Testing
@testable import Bubo

/// The bridge source and the user's `claude` and `bun`, for the live tests.
nonisolated enum LiveTools {
    static let bridge = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "bridge")

    /// Both executables, or `nil` when one of them or `bridge/node_modules` is missing.
    static let found: (claude: URL, bun: URL)? = {
        let home = URL.homeDirectory.path
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: bridge.appending(path: "node_modules").path),
              let claude = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
                .first(where: { fileManager.isExecutableFile(atPath: $0) }),
              let bun = ["\(home)/.bun/bin/bun", "/opt/homebrew/bin/bun", "/usr/local/bin/bun"]
                .first(where: { fileManager.isExecutableFile(atPath: $0) })
        else { return nil }
        return (URL(filePath: claude), URL(filePath: bun))
    }()
}

/// The user's real `claude`, started by the bridge source, in a repo with a `SessionStart` hook and a `.mcp.json`.
///
/// No login and no network: `CLAUDE_CONFIG_DIR` points to an empty folder, so `claude` stops at
/// "Not logged in", after the repo's hooks and MCP servers would have started. Needs `claude`, `bun`
/// and `bridge/node_modules` (the app build installs them); skipped otherwise.
@Suite(.timeLimit(.minutes(2)), .enabled(if: LiveTools.found != nil, "Servono claude, bun e bridge/node_modules"))
struct TrustGateLiveTests {

    let work: URL
    let repo: URL
    let configuration: URL
    let gate: TrustGate
    let claude: URL
    let agent: AgentBridge

    init() throws {
        let tools = try #require(LiveTools.found)
        claude = tools.claude
        work = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "TrustGateLive-\(UUID().uuidString)", directoryHint: .isDirectory)
        repo = work.appending(path: "repo", directoryHint: .isDirectory)
        configuration = work.appending(path: "config", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo.appending(path: ".claude"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configuration, withIntermediateDirectories: true)
        gate = TrustGate(configuration: configuration.appending(path: ".claude.json"))
        var environment = ChildEnvironment.make(claude: claude)
        environment["CLAUDE_CONFIG_DIR"] = configuration.path
        agent = AgentBridge(executable: tools.bun, arguments: ["run", LiveTools.bridge.appending(path: "src/main.ts").path],
                            environment: environment, trustGate: gate) { _, _ in "" }
    }

    var hookRan: URL { work.appending(path: "hook-ran") }
    var serverStarted: URL { work.appending(path: "server-started") }

    func makeRepo() async throws {
        try await git("init", "-q")
        try Data(#"""
            {"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "touch '\#(hookRan.path)'"}]}]},
             "permissions": {"allow": ["Bash(ls:*)"]}}
            """#.utf8).write(to: repo.appending(path: ".claude/settings.json"))
        try Data(#"{"mcpServers": {"spia": {"command": "/usr/bin/touch", "args": ["\#(serverStarted.path)"]}}}"#.utf8)
            .write(to: repo.appending(path: ".mcp.json"))
    }

    @discardableResult
    func git(_ arguments: String...) async throws -> ProcessOutput {
        let output = try await ProcessRunner.live.run(URL(filePath: "/usr/bin/git"),
                                                      ["-C", repo.path, "-c", "user.name=Bubo", "-c", "user.email=bubo@example.com"] + arguments)
        try #require(output.exitCode == 0, "git \(arguments): \(output.standardError)")
        return output
    }

    /// Starts a Sessione-like conversation in `folder`; without a login it fails, after the hooks.
    func startClaude(in folder: URL) async {
        _ = try? await agent.ask("Rispondi: ok", in: folder).reduce("", +)
    }

    /// Whether the CLI itself, run in `folder`, warns that the workspace is not trusted.
    func cliWarnsUntrusted(in folder: URL) async throws -> Bool {
        let output = try await ProcessRunner.live.run(URL(filePath: "/bin/sh"), [
            "-c", #"cd "$1" && exec /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin CLAUDE_CONFIG_DIR="$2" "$3" -p ok --setting-sources user,project"#,
            "sh", folder.path, configuration.path, claude.path,
        ])
        return output.standardError.contains("this workspace has not been trusted")
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test func theRepoTurnsOnOnlyAfterTrustAndUntilRevoked() async throws {
        try await makeRepo()

        await startClaude(in: repo)
        #expect(!exists(hookRan), "L'hook del repo è partito prima della fiducia.")
        #expect(!exists(serverStarted), "Un server di .mcp.json è partito prima della fiducia.")
        #expect(try await cliWarnsUntrusted(in: repo))

        try gate.trust(repo)
        #expect(try await !cliWarnsUntrusted(in: repo))
        try FileManager.default.removeItem(at: hookRan)
        await startClaude(in: repo)
        #expect(exists(hookRan), "Dopo Fidati l'hook del repo non è partito.")

        try await git("add", "-A")
        try await git("commit", "-qm", "repo")
        let worktree = work.appending(path: "worktree", directoryHint: .isDirectory)
        try await git("worktree", "add", "-q", worktree.path)
        try FileManager.default.removeItem(at: hookRan)
        await startClaude(in: worktree)
        #expect(exists(hookRan), "Il worktree di un Progetto fidato non è fidato.")

        try gate.revoke(repo)
        try FileManager.default.removeItem(at: hookRan)
        await startClaude(in: repo)
        #expect(!exists(hookRan), "Dopo la revoca l'hook del repo è partito.")
    }
}
