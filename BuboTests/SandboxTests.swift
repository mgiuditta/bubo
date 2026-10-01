import Foundation
import Testing
@testable import Bubo

struct SandboxTests {
    static let environment = ["HOME": "/Users/u", "PATH": "/usr/bin", "ANTHROPIC_API_KEY": "k", "GH_TOKEN": "t",
                              "AWS_PROFILE": "p", "DB_PASSWORD": "x", "TOKEN_COUNT": "3"]

    static func policy() -> SandboxPolicy {
        SandboxPolicy(environment: environment, userTemporaryFolder: "/var/folders/x/T", userCacheFolder: "/var/folders/x/C")
    }

    @Test func thePresetWritesInTheCachesAndReachesOnlyThePackageRegistries() throws {
        let object = Self.policy().jsonObject
        let filesystem = try #require(object["filesystem"] as? [String: [String]])
        #expect(filesystem["allowWrite"] == ["/var/folders/x/T", "/var/folders/x/C"]
            + SandboxPolicy.presetFolders.map { "/Users/u/\($0)" })
        let network = try #require(object["network"] as? [String: Any])
        let domains = try #require(network["allowedDomains"] as? [String])
        #expect(domains.contains("registry.npmjs.org"))
        #expect(!domains.contains { $0.contains("github") })
        #expect(network["allowLocalBinding"] as? Bool == true)
        // A host outside the list becomes a Richiesta "Rete: host" (#216), no longer a denial.
        #expect(network["strictAllowlist"] as? Bool == false)
    }

    @Test(arguments: ["/Users/u/.npm", "/Users/u/Library/pnpm/store", "/Users/u/Library/Caches/Yarn",
                      "/Users/u/.yarn/berry", "/Users/u/.bun/install/cache", "/Users/u/.cargo/registry",
                      "/Users/u/.cargo/git", "/Users/u/.cargo/.package-cache", "/Users/u/Library/Caches/pip",
                      "/Users/u/.cache/uv", "/Users/u/go/pkg/mod", "/Users/u/Library/Caches/go-build"])
    func theDevelopmentToolsWriteInTheirCachesWithoutConfiguration(cache: String) {
        #expect(Self.policy().writablePaths.contains(cache))
    }

    @Test func theFoldersOfCodeThatRunsOutsideStayClosed() {
        let paths = Self.policy().writablePaths
        let closed = [".cargo", ".cargo/bin", ".cargo/config.toml", ".bun", ".bun/bin", "go", "go/bin", "Library/pnpm",
                      "Library/Developer/Xcode/DerivedData", ".gradle", ".m2"]
        #expect(closed.map { "/Users/u/\($0)" }.allSatisfy { !paths.contains($0) })
    }

    @Test func ghRunsOutsideTheSandboxThroughThePermissions() {
        #expect(Self.policy().jsonObject["excludedCommands"] as? [String] == ["gh", "gh *"])
    }

    @Test func itNeverRunsWithoutTheSandbox() {
        let object = Self.policy().jsonObject
        #expect(object["enabled"] as? Bool == true)
        #expect(object["failIfUnavailable"] as? Bool == true)
    }

    @Test func theCredentialsAreDenied() throws {
        let credentials = try #require(Self.policy().jsonObject["credentials"] as? [String: [[String: String]]])
        #expect(credentials["files"]?.compactMap { $0["path"] }
            == ["/Users/u/.ssh", "/Users/u/.aws", "/Users/u/.gnupg", "/Users/u/.netrc"])
        #expect(credentials["files"]?.allSatisfy { $0["mode"] == "deny" } == true)
        #expect(credentials["envVars"]?.compactMap { $0["name"] }
            == ["ANTHROPIC_API_KEY", "AWS_PROFILE", "DB_PASSWORD", "GH_TOKEN"])
    }

    @Test func theDarwinTemporaryFolderIsRead() throws {
        let folder = try #require(SandboxPolicy.darwinFolder(_CS_DARWIN_USER_TEMP_DIR))
        #expect(folder.hasPrefix("/") && !folder.hasSuffix("/"))
    }

    @Test func askCarriesTheSandboxOnlyWhenOn() throws {
        let on = try BridgeCommand.ask(id: "a1", prompt: "x", directory: URL(filePath: "/tmp"), settingSources: [],
                                       sandbox: Self.policy()).line()
        let object = try #require(try JSONSerialization.jsonObject(with: on) as? [String: Any])
        #expect((object["sandbox"] as? [String: Any])?["enabled"] as? Bool == true)
        let off = try BridgeCommand.ask(id: "a1", prompt: "x", directory: URL(filePath: "/tmp"), settingSources: []).line()
        #expect(!String(decoding: off, as: UTF8.self).contains("sandbox"))
    }

    @Test func theSandboxThatDidNotStartIsAnEventOfItsOwn() throws {
        let line = #"{"v":4,"type":"sandboxUnavailable","id":"a1","reason":"profilo rifiutato"}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8))
            == .sandboxUnavailable(id: "a1", reason: "profilo rifiutato"))
    }

    @Test(arguments: [
        (true, nil, SandboxState.on), (false, nil, .off), (true, true, .on), (false, false, .off),
        (true, false, .onFromNextTurn), (false, true, .offFromNextTurn),
    ] as [(Bool, Bool?, SandboxState)])
    func theIndicatorFollowsTheTurnInProgress(isEnabled: Bool, currentTurn: Bool?, expected: SandboxState) {
        #expect(SandboxState(isEnabled: isEnabled, currentTurn: currentTurn) == expected)
    }

    @MainActor
    @Test func theSwitchIsKeptByProgetto() throws {
        let suite = "SandboxTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = URL(filePath: "/tmp/progetto/", directoryHint: .isDirectory)

        SandboxStore(defaults: defaults).setEnabled(true, in: project)

        let store = SandboxStore(defaults: defaults)
        #expect(store.isEnabled(in: URL(filePath: "/tmp/progetto")))
        #expect(!store.isEnabled(in: URL(filePath: "/tmp/altro")))
        store.setEnabled(false, in: project)
        #expect(!SandboxStore(defaults: defaults).isEnabled(in: project))
    }

    /// A bridge played by `/bin/sh` that writes every command to `log`: the first turn's Sandbox does not start,
    /// the next turns end at once.
    static func sandboxBridge(log: URL) -> AgentBridge {
        let script = #"""
            turns=0
            while read line; do
                echo "$line" >> "$1"
                id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                case "$line" in
                    *'"type":"ask"'*)
                        turns=$((turns + 1))
                        if [ $turns = 1 ]; then
                            echo "{\"v\":4,\"type\":\"sandboxUnavailable\",\"id\":\"$id\",\"reason\":\"profilo rifiutato\"}"
                        else
                            echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
                        fi ;;
                esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", log.path],
                           environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/u"]) { _, _, _ in "" }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func aSessionWhoseSandboxDoesNotStartSaysWhyAndRetries() async throws {
        let temporary = FileManager.default.temporaryDirectory
        let log = temporary.appending(path: "bridge-\(UUID().uuidString).log")
        let file = temporary.appending(path: "Sessioni-\(UUID().uuidString).json")
        let suite = "SandboxTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
            defaults.removePersistentDomain(forName: suite)
        }
        let project = URL(filePath: "/tmp")
        let sandbox = SandboxStore(defaults: defaults)
        sandbox.setEnabled(true, in: project)
        let bridge = Self.sandboxBridge(log: log)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: temporary), sandbox: sandbox) { bridge }

        try store.start("Scrivi i test", title: "Prova", branch: "", in: project, onCheckout: true)
        try await SessionTests.wait { store.sessions.first?.activity == .errore }
        let failed = try #require(store.sessions.first)
        let reason = "profilo rifiutato"
        #expect(failed.failure == String(localized: "Sandbox non disponibile: \(reason). La Sessione non è partita."))
        #expect(failed.unstartedPrompt == "Scrivi i test")
        #expect(try String(contentsOf: log, encoding: .utf8).contains(#""failIfUnavailable":true"#))

        store.retry(failed.id)
        try await SessionTests.wait { store.sessions.first?.activity == .ferma }
        let retried = try #require(store.sessions.first)
        #expect(retried.activity == .ferma)
        #expect(retried.unstartedPrompt == nil)
        let asks = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").filter { $0.contains(#""type":"ask""#) }
        #expect(asks.count == 2)
        #expect(asks.allSatisfy { $0.contains(#""prompt":"Scrivi i test""#) && $0.contains(#""sandbox":{"#) })
    }
}
