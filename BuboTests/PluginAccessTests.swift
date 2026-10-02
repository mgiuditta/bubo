import Foundation
import Synchronization
import Testing
@testable import Bubo

/// The Impostazioni of a plugin and the login to the MCP servers (#210): secrets only on standard input, the form
/// from `configure --json`, Accedi with the command when it fails, `needs-auth` in Da sistemare. A fake `claude`:
/// nothing touches `~/.claude`, the Keychain or a real server.
@MainActor
struct PluginAccessTests {
    nonisolated static let plugin = PluginID(name: "uno", marketplace: "prova")
    nonisolated static let secret = "sk-segreto-0123456789"

    /// What `claude plugin configure uno@prova --json` printed for a plugin with every kind of option (CLI 2.1.287).
    nonisolated static let configureJSON = """
        {
          "pluginId": "uno@prova",
          "displayName": "uno",
          "schema": {
            "api_key": {"type": "string", "title": "Chiave API", "description": "La chiave", "required": true, "sensitive": true},
            "region": {"type": "string", "title": "Regione", "description": "Dove", "default": "eu", "options": ["eu", "us"]},
            "count": {"type": "number", "title": "Quanti", "description": "n", "min": 1, "max": 10},
            "verbose": {"type": "boolean", "title": "Verboso", "description": "v"},
            "dir": {"type": "directory", "title": "Cartella", "description": "d"},
            "file": {"type": "file", "title": "File", "description": "f", "required": true}
          },
          "inputs": {"api_key": "\(secret)", "region": "us", "count": "3", "verbose": "false", "dir": "", "file": ""},
          "choices": {"region": ["eu", "us"], "verbose": ["true", "false"]},
          "configured": ["api_key", "region", "count"],
          "unconfigured": ["verbose", "dir", "file"]
        }
        """

    // MARK: Impostazioni

    @Test func secretsGoOnStandardInputNeverInTheArguments() throws {
        let command = PluginCommand.configure(Self.plugin, values: PluginOptionValues(["api_key": Self.secret, "count": "3"]))
        #expect(command.arguments == ["plugin", "configure", "uno@prova", "--values-stdin", "--json"])
        let input = try #require(command.input)
        let object = try #require(try JSONSerialization.jsonObject(with: input) as? [String: String])
        #expect(object == ["api_key": Self.secret, "count": "3"])
        // Interpolated in a log line, or printed by a test failure, the values never show.
        #expect(!String(describing: command).contains(Self.secret))
        #expect(!String(reflecting: command).contains(Self.secret))
    }

    @Test func configureSendsTheValuesToClaudeAndReadsWhatItSaved() async throws {
        let seen = Mutex<(arguments: [String], input: Data?)>(([], nil))
        let cli = PluginCLI(run: { arguments, _, input in
            seen.withLock { $0 = (arguments, input) }
            return ProcessOutput(exitCode: 0, standardOutput: #"{"pluginId": "uno@prova", "saved": ["api_key"], "unconfigured": []}"#)
        }, home: URL.temporaryDirectory, queue: PluginWriteQueue())
        let result = try await cli.perform(.configure(Self.plugin, values: PluginOptionValues(["api_key": Self.secret])), project: nil)
        #expect(result.succeeded)
        let (arguments, input) = seen.withLock { $0 }
        #expect(!arguments.contains { $0.contains(Self.secret) })
        #expect(String(decoding: try #require(input), as: UTF8.self).contains(Self.secret))
    }

    @Test func aRefusedValueGivesTheMessageOfClaude() async throws {
        let cli = PluginCLI(run: { _, _, _ in
            ProcessOutput(exitCode: 1, standardOutput: """
                {
                  "pluginId": "uno@prova",
                  "refused": {"option": "count", "message": "Quanti: It takes a number between 1 and 10."}
                }
                """)
        }, home: URL.temporaryDirectory, queue: PluginWriteQueue())
        let result = try await cli.perform(.configure(Self.plugin, values: PluginOptionValues(["count": "99"])), project: nil)
        #expect(!result.succeeded)
        #expect(result.message == "Quanti: It takes a number between 1 and 10.")
    }

    @Test func theFormHasTheOptionsInTheOrderOfTheManifestAndNoSecret() throws {
        let options = try #require(PluginOptions(json: Self.configureJSON))
        #expect(options.options.map(\.id) == ["api_key", "region", "count", "verbose", "dir", "file"])
        #expect(options.options.map(\.kind) == [.string, .string, .number, .boolean, .directory, .file])
        #expect(options.options.first?.isSensitive == true)
        #expect(options.options[1].choices == ["eu", "us"])
        #expect(options.options[3].choices.isEmpty, "a boolean is a switch")
        #expect(options.values["api_key"] == nil)
        #expect(!options.values.values.contains(Self.secret))
        #expect(options.missingRequired.map(\.id) == ["file"])
    }

    @Test func onlyTheChangedValuesAndTheTypedSecretsAreSaved() throws {
        let options = try #require(PluginOptions(json: Self.configureJSON))
        var edited = options.values
        #expect(options.changes(in: edited).values.isEmpty, "an empty secret keeps the saved one")
        edited["count"] = " 4 "
        edited["api_key"] = Self.secret
        #expect(options.changes(in: edited).values == ["count": "4", "api_key": Self.secret])
    }

    @Test func aPluginHasImpostazioniOnlyWhenItsManifestDeclaresThem() async throws {
        let home = try PluginHome()
        let with = home.home.appending(path: "con", directoryHint: .isDirectory)
        let without = home.home.appending(path: "senza", directoryHint: .isDirectory)
        try home.write(["name": "con", "userConfig": ["k": ["type": "string", "title": "K", "description": "k"]]],
                       at: with.appending(path: ".claude-plugin/plugin.json").path)
        try home.write(["name": "senza"], at: without.appending(path: ".claude-plugin/plugin.json").path)
        #expect(await PluginOptions.areDeclared(at: with))
        #expect(await !PluginOptions.areDeclared(at: without))
        #expect(await !PluginOptions.areDeclared(at: nil))
    }

    @Test func theValuesReachTheChildOnlyOnStandardInput() async throws {
        let output = try await ProcessRunner.disclaimed(environment: ["PATH": "/usr/bin:/bin"], input: Data(Self.secret.utf8))
            .run(URL(filePath: "/bin/cat"), [])
        #expect(output.exitCode == 0)
        #expect(output.standardOutput == Self.secret)
    }

    /// With the user's real `claude` in a temporary `HOME`: no secret, so nothing reaches the Keychain.
    @Test(.enabled(if: LiveClaude.found != nil, "Serve claude"), .timeLimit(.minutes(1)))
    func claudeSavesWhatTheFormSends() async throws {
        let home = try PluginHome()
        let root = URL(filePath: TrustGate.realPath(home.home.path), directoryHint: .isDirectory)
        let environment = PluginListing.environment(base: ["HOME": root.path])
        let marketplace = root.appending(path: "mercato", directoryHint: .isDirectory)
        // As text: the order of the options is the manifest's, which a dictionary would lose.
        try home.write(Data(#"""
            {"name": "uno", "version": "1.0.0", "userConfig": {
              "region": {"type": "string", "title": "Regione", "description": "Dove", "options": ["eu", "us"], "required": true},
              "count": {"type": "number", "title": "Quanti", "description": "n"}}}
            """#.utf8), at: marketplace.appending(path: "plugins/uno/.claude-plugin/plugin.json").path)
        try home.write(["name": "prova", "owner": ["name": "Prova"], "plugins": [["name": "uno", "source": "./plugins/uno"]]],
                       at: marketplace.appending(path: ".claude-plugin/marketplace.json").path)
        let claude = try #require(LiveClaude.found)
        let runner = ProcessRunner.disclaimed(environment: environment, in: root)
        try #require(try await runner.run(claude, ["plugin", "marketplace", "add", marketplace.path]).exitCode == 0)
        try #require(try await runner.run(claude, ["plugin", "install", "uno@prova", "--scope", "user", "--json"]).exitCode == 0)
        let cli = PluginCLI.live(locator: ClaudeLocator(isExecutable: { $0 == claude }), environment: environment)

        let before = try await cli.options(of: Self.plugin, project: nil)
        #expect(before.options.map(\.id) == ["region", "count"])
        #expect(before.missingRequired.map(\.id) == ["region"])
        let saved = try await cli.perform(.configure(Self.plugin, values: PluginOptionValues(["region": "us", "count": "3"])),
                                          project: nil)
        #expect(saved.succeeded, "\(saved.message)")
        let after = try await cli.options(of: Self.plugin, project: nil)
        #expect(after.values["region"] == "us")
        #expect(after.missingRequired.isEmpty)
        let refused = try await cli.perform(.configure(Self.plugin, values: PluginOptionValues(["region": "zz"])), project: nil)
        #expect(!refused.succeeded)
        #expect(!refused.message.isEmpty)
    }

    // MARK: MCP servers

    @Test func accediRunsMcpLoginAndSaysWhetherItSucceeded() async throws {
        let seen = Mutex<[String]>([])
        let succeeding = MCPLogin { arguments, _ in
            seen.withLock { $0 = arguments }
            return ProcessOutput(exitCode: 0, standardOutput: "")
        }
        #expect(try await succeeding.logIn(to: "linear", in: URL.temporaryDirectory))
        #expect(seen.withLock { $0 } == ["mcp", "login", "--", "linear"])

        let failing = MCPLogin { _, _ in ProcessOutput(exitCode: 1, standardOutput: "No MCP server named \"linear\".") }
        #expect(try await !failing.logIn(to: "linear", in: URL.temporaryDirectory))
        let missing = MCPLogin { _, _ in throw PluginCLIError.claudeMissing }
        #expect(try await !missing.logIn(to: "linear", in: URL.temporaryDirectory))
    }

    @Test func aLoginThatDoesNotEndIsStopped() async throws {
        let stopped = Mutex(false)
        var login = MCPLogin { _, _ in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                stopped.withLock { $0 = true }
                throw error
            }
            return ProcessOutput(exitCode: 0, standardOutput: "")
        }
        login.timeout = .milliseconds(50)
        #expect(try await !login.logIn(to: "linear", in: URL.temporaryDirectory))
        #expect(stopped.withLock { $0 })
        #expect(MCPLogin.live().timeout == .seconds(300))
    }

    @Test(arguments: [
        ("linear", nil, "claude mcp login linear"),
        ("plugin:figma:figma", "/Users/u/Il mio progetto", "cd '/Users/u/Il mio progetto' && claude mcp login plugin:figma:figma"),
        ("l'altro", nil, #"claude mcp login 'l'\''altro'"#),
        ("-x", nil, "claude mcp login '-x'"),
    ] as [(String, String?, String)])
    func theCommandToCopyIsOneTheShellReadsAsIs(server: String, project: String?, expected: String) {
        #expect(MCPLogin.commandLine(for: server, in: project.map { URL(filePath: $0) }) == expected)
    }

    @Test func serversWaitingForALoginAreInDaSistemare() async throws {
        let home = try PluginHome()
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(PluginList()), configuration: { _ in
            Self.configuration(linear: "needs-auth")
        })
        let following = Task { await catalog.follow(project: home.project) }
        defer { following.cancel() }
        try await waitForCondition { !catalog.servers.isEmpty }

        #expect(catalog.serversNeedingAuthentication.map(\.name) == ["linear"])
        let snapshot = try #require(catalog.snapshot)
        #expect(snapshot.problems.isEmpty)
        #expect(PluginSidebarItem.initialSelection(in: snapshot, serversNeedingAuthentication: 1) == .toFix)
    }

    @Test func afterALoginTheTurnsReconnectAndTheStatusIsReadAgain() async throws {
        let home = try PluginHome()
        let reads = Mutex(0)
        let reconnected = Mutex<[String]>([])
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(PluginList()),
                                    login: MCPLogin { _, _ in ProcessOutput(exitCode: 0, standardOutput: "") },
                                    reconnect: { name in reconnected.withLock { $0.append(name) } }, configuration: { _ in
            let count = reads.withLock { $0 += 1; return $0 }
            return Self.configuration(linear: count == 1 ? "needs-auth" : "connected")
        })
        let following = Task { await catalog.follow(project: home.project) }
        defer { following.cancel() }
        try await waitForCondition { !catalog.serversNeedingAuthentication.isEmpty }

        #expect(try await catalog.logIn(to: "linear"))
        #expect(reconnected.withLock { $0 } == ["linear"])
        #expect(catalog.serversNeedingAuthentication.isEmpty)
    }

    @Test func aFailedLoginReconnectsNothing() async throws {
        let home = try PluginHome()
        let reconnected = Mutex(false)
        let catalog = PluginCatalog(folders: home.folders, listing: .answering(PluginList()),
                                    login: MCPLogin { _, _ in ProcessOutput(exitCode: 1, standardOutput: "") },
                                    reconnect: { _ in reconnected.withLock { $0 = true } }, configuration: { _ in
            Self.configuration(linear: "needs-auth")
        })
        let following = Task { await catalog.follow(project: home.project) }
        defer { following.cancel() }
        try await waitForCondition { !catalog.servers.isEmpty }

        #expect(try await !catalog.logIn(to: "linear"))
        #expect(!reconnected.withLock { $0 })
        #expect(catalog.serversNeedingAuthentication.count == 1)
    }

    @Test func theBridgeTellsTheTurnsInProgressToReconnect() throws {
        let line = try BridgeCommand.reconnectMCPServer(name: "linear").line()
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(object["type"] as? String == "reconnect")
        #expect(object["server"] as? String == "linear")
    }

    nonisolated private static func configuration(linear status: String) -> ClaudeConfiguration {
        ClaudeConfiguration(skills: [], plugins: [], pluginErrors: [],
                            mcpServers: [.init(name: "linear", status: status, source: "claudeai", error: nil),
                                         .init(name: "db", status: "connected", source: "project", error: nil)],
                            instructions: [])
    }
}
