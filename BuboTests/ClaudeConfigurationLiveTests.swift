import Foundation
import Testing
@testable import Bubo

/// The configuration panel against the CLI itself on the same folder, with the user's real `claude` started by the
/// bridge source.
///
/// No login and no Quota: `CLAUDE_CONFIG_DIR` points to a folder of the test, and both sides run `/context`, a local
/// command that never reaches the model. Needs `claude`, `bun` and `bridge/node_modules`; skipped otherwise.
@Suite(.timeLimit(.minutes(2)), .enabled(if: LiveTools.found != nil, "Servono claude, bun e bridge/node_modules"))
struct ClaudeConfigurationLiveTests {

    let repo: URL
    let configuration: URL
    let gate: TrustGate
    let claude: URL
    let agent: AgentBridge

    init() throws {
        let tools = try #require(LiveTools.found)
        claude = tools.claude
        let work = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "ClaudeConfigurationLive-\(UUID().uuidString)", directoryHint: .isDirectory)
        repo = work.appending(path: "repo", directoryHint: .isDirectory)
        configuration = work.appending(path: "config", directoryHint: .isDirectory)
        try Self.write("---\nname: progetto\ndescription: Una skill del Progetto\n---\nciao\n",
                       to: repo.appending(path: ".claude/skills/progetto/SKILL.md"))
        try Self.write("# Progetto\n", to: repo.appending(path: "CLAUDE.md"))
        try Self.write("---\nname: agente-progetto\ndescription: Un agente del Progetto\ntools: Read\n---\n",
                       to: repo.appending(path: ".claude/agents/sotto/agente.md"))
        try Self.write("---\nname: agente-utente\ndescription: Un agente dell'utente\n---\n",
                       to: configuration.appending(path: "agents/agente-utente.md"))
        try Self.write(#"{"mcpServers": {"del-progetto": {"command": "/usr/bin/true"}}}"#, to: repo.appending(path: ".mcp.json"))
        try Self.write("---\nname: utente\ndescription: Una skill dell'utente\n---\nciao\n",
                       to: configuration.appending(path: "skills/utente/SKILL.md"))
        try Self.write(#"{"mcpServers": {"dell-utente": {"command": "/usr/bin/true"}}}"#,
                       to: configuration.appending(path: ".claude.json"))
        gate = TrustGate(configuration: configuration.appending(path: ".claude.json"))
        var environment = ChildEnvironment.make(claude: claude)
        environment["CLAUDE_CONFIG_DIR"] = configuration.path
        agent = AgentBridge(executable: tools.bun, arguments: ["run", LiveTools.bridge.appending(path: "src/main.ts").path],
                            environment: environment, trustGate: gate) { _, _ in "" }
    }

    static func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    /// The `init` message of the CLI itself, run in `folder` with `sources`.
    func cliInit(in folder: URL, sources: String) async throws -> CLIInit {
        let output = try await ProcessRunner.live.run(URL(filePath: "/bin/sh"), [
            "-c", #"cd "$1" && exec /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin CLAUDE_CONFIG_DIR="$2" "$3" -p /context --output-format stream-json --verbose --setting-sources "$4""#,
            "sh", folder.path, configuration.path, claude.path, sources,
        ])
        let line = try #require(output.standardOutput.split(separator: "\n").first { $0.contains(#""subtype":"init""#) },
                                "La CLI non ha mandato init: \(output.standardError)")
        return try JSONDecoder().decode(CLIInit.self, from: Data(line.utf8))
    }

    /// Every path under the configuration folder but `.claude.json`, which the CLI rewrites at each start.
    func configurationFiles() -> Set<String> {
        let paths = FileManager.default.enumerator(atPath: configuration.path)?.compactMap { $0 as? String } ?? []
        return Set(paths.filter { $0 != ".claude.json" })
    }

    /// The paths added or removed since `before`, once `claude` exited: while it runs, it lists itself in `sessions/`.
    func filesWritten(since before: Set<String>) async throws -> Set<String> {
        for _ in 0..<20 where configurationFiles() != before {
            try await Task.sleep(for: .milliseconds(100))
        }
        return configurationFiles().symmetricDifference(before)
    }

    @Test func theCountsMatchTheCLIAndNothingIsWritten() async throws {
        try gate.trust(repo)
        let cli = try await cliInit(in: repo, sources: "user,project,local")
        let before = configurationFiles()

        let shown = try await agent.configuration(of: repo)

        #expect(shown.loadsProject)
        #expect(shown.skills.count == cli.skills.count)
        #expect(Set(shown.skills) == Set(cli.skills))
        #expect(shown.plugins.count == cli.plugins.count)
        #expect(shown.mcpServers.count == cli.mcpServers.count)
        #expect(Set(shown.mcpServers.map(\.name)) == Set(cli.mcpServers.map(\.name)))
        #expect(shown.skills.contains("progetto") && shown.skills.contains("utente"))
        #expect(Set(shown.mcpServers.map(\.name)).isSuperset(of: ["del-progetto", "dell-utente"]))
        #expect(shown.instructions.map(\.path) == [repo.appending(path: "CLAUDE.md").path])
        // `supportedAgents()`: the files of both sources, by their `name`, next to the built-in agents.
        #expect(shown.agents.contains(.init(name: "agente-progetto", description: "Un agente del Progetto", model: nil)))
        #expect(shown.agents.contains { $0.name == "agente-utente" })
        #expect(shown.agents.count > 2)
        let written = try await filesWritten(since: before)
        #expect(written.isEmpty, "Il pannello ha scritto nella cartella di configurazione: \(written)")

        // Warm bridge: from the request to the configuration, `init` included.
        let start = ContinuousClock.now
        _ = try await agent.configuration(of: repo)
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func anUntrustedProgettoShowsOnlyTheUsersConfiguration() async throws {
        let cli = try await cliInit(in: repo, sources: "user")

        let shown = try await agent.configuration(of: repo)

        #expect(!shown.loadsProject)
        #expect(Set(shown.skills) == Set(cli.skills))
        #expect(shown.skills.contains("utente") && !shown.skills.contains("progetto"))
        #expect(shown.mcpServers.map(\.name) == ["dell-utente"])
        #expect(shown.instructions.isEmpty)
        let agents = Set(shown.agents.map(\.name))
        #expect(agents.contains("agente-utente") && !agents.contains("agente-progetto"))
    }
}

/// The part of the CLI's `init` message the panel counts.
nonisolated struct CLIInit: Decodable {
    struct Named: Decodable {
        let name: String
    }

    let skills: [String]
    let plugins: [Named]
    let mcpServers: [Named]

    private enum CodingKeys: String, CodingKey {
        case skills, plugins
        case mcpServers = "mcp_servers"
    }
}
