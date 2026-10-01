import Foundation
import Testing
@testable import Bubo

/// The blocks of the Sandbox and its network on Bubo's side (#216): the row of each block, Consenti in questo Progetto,
/// the Richiesta "Rete: host" and where its answers go. The reading of `sandbox_violations` is tested in
/// `bridge/src/violations.test.ts`.
struct SandboxNetworkTests {
    let session = UUID()

    static func network(_ id: String, _ host: String) -> PermissionRequest {
        PermissionRequest(id: id, tool: PermissionRequest.networkTool, host: host)
    }

    static func defaults() throws -> (UserDefaults, String) {
        let suite = "SandboxNetworkTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    // MARK: Blocks

    @Test func aBlockArrivesAsProgressOfItsConversation() throws {
        let line = #"{"v":4,"type":"sandboxBlock","id":"a1","kind":"network","target":"example.com"}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8))
            == .progress(id: "a1", .sandboxBlock(SandboxBlock(kind: .network, target: "example.com"))))
        let newer = #"{"v":4,"type":"sandboxBlock","id":"a1","kind":"socket","target":"/var/run/x.sock"}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(newer.utf8))
            == .progress(id: "a1", .sandboxBlock(SandboxBlock(kind: .other, target: "/var/run/x.sock"))))
    }

    // Criterio di accettazione: 100% dei blocchi registrati mostrati con percorso o host.
    @Test(arguments: [
        (SandboxBlock(kind: .write, target: "/Users/u/fuori/a.txt"), "/Users/u/fuori/a.txt"),
        (SandboxBlock(kind: .read, target: "/Users/u/.ssh/id_ed25519"), "/Users/u/.ssh/id_ed25519"),
        (SandboxBlock(kind: .network, target: "example.com"), "example.com"),
        (SandboxBlock(kind: .other, target: "com.apple.trustd", operation: "mach-lookup"), "com.apple.trustd"),
        (SandboxBlock(kind: .other, target: "una riga che nessuno sa leggere"), "una riga che nessuno sa leggere"),
    ])
    func everyBlockIsOneLineWithItsPathOrHost(block: SandboxBlock, target: String) {
        #expect(block.line.hasSuffix(target))
        #expect(block.line.count > target.count)
        #expect(!block.line.contains("\n"))
    }

    @Test func theLinesSayWhatWasStopped() {
        #expect(SandboxBlock(kind: .write, target: "/x/a").line == String(localized: "Bloccato dalla sandbox: scrittura in \("/x/a")"))
        #expect(SandboxBlock(kind: .network, target: "a.dev").line == String(localized: "Bloccato dalla sandbox: rete verso \("a.dev")"))
    }

    @Test func consentiAddsTheHostOrTheExactFolderOfTheWrite() {
        #expect(SandboxBlock(kind: .network, target: "API.Example.com").allowance == .domain("api.example.com"))
        #expect(SandboxBlock(kind: .write, target: "/Users/u/.cache/tool/a.txt").allowance == .folder("/Users/u/.cache/tool"))
        // Reads stay denied: the Sandbox denies the credentials on purpose.
        #expect(SandboxBlock(kind: .read, target: "/Users/u/.ssh/id_ed25519").allowance == nil)
        #expect(SandboxBlock(kind: .other, target: "com.apple.trustd", operation: "mach-lookup").allowance == nil)
        #expect(SandboxBlock(kind: .network, target: "::1").allowance == nil)
    }

    @Test(arguments: ["/a.txt", "/tmp/a.txt", "/Users/u/a.txt", "/Users/a.txt", "relativo/a.txt", "/Users/u/x/../../a"])
    func aFolderTooWideIsNeverOffered(path: String) {
        #expect(SandboxAllowance.folder(ofBlocked: path, home: "/Users/u") == nil)
    }

    // MARK: Store and policy

    // Criterio di accettazione: 0 scritture nei settings. Lo store è nei default di Bubo.
    @Test func theAllowancesLiveInBubosDefaultsAndReachThePolicy() throws {
        let (defaults, suite) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = URL(filePath: "/Users/u/repo/")
        let store = SandboxStore(defaults: defaults)
        store.allow(.domain("api.example.com"), in: project)
        store.allow(.domain("api.example.com"), in: project)
        store.allow(.folder("/Users/u/.cache/tool"), in: project)
        store.allow(.domain("registry.npmjs.org"), in: project)

        let reopened = SandboxStore(defaults: defaults).allowances(in: URL(filePath: "/Users/u/repo"))
        #expect(reopened == SandboxAllowances(domains: ["api.example.com", "registry.npmjs.org"], folders: ["/Users/u/.cache/tool"]))
        #expect(SandboxStore(defaults: defaults).allowances(in: URL(filePath: "/Users/u/altro")) == SandboxAllowances())

        let object = SandboxPolicy(environment: SandboxTests.environment, userTemporaryFolder: "/T", userCacheFolder: "/C",
                                   allowances: reopened).jsonObject
        let domains = try #require((object["network"] as? [String: Any])?["allowedDomains"] as? [String])
        #expect(domains == SandboxPolicy.presetDomains + ["api.example.com"])
        let folders = try #require((object["filesystem"] as? [String: [String]])?["allowWrite"])
        #expect(folders.last == "/Users/u/.cache/tool")

        store.remove(.domain("api.example.com"), in: project)
        store.remove(.folder("/Users/u/.cache/tool"), in: project)
        #expect(SandboxStore(defaults: defaults).allowances(in: project).domains == ["registry.npmjs.org"])
        #expect(SandboxStore(defaults: defaults).allowances(in: project).folders.isEmpty)
    }

    // MARK: Richiesta "Rete: host"

    @Test func theRichiestaCarriesTheHostAndIsLevel3() throws {
        let line = #"{"v":4,"type":"permission","id":"a1","request":"p1","tool":"SandboxNetworkAccess","host":"api.example.com","description":"Allow network connection to api.example.com?"}"#
        guard case let .permission(_, request) = try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) else {
            Issue.record("not a Richiesta")
            return
        }
        #expect(request.host == "api.example.com")
        #expect(request.subject == "api.example.com")
        #expect(RiskClassifier(workingDirectory: URL(filePath: "/tmp/wt")).risk(of: request) == Risk(level: .rete))
    }

    @Test func itOffersTheUsualAnswersAndSavesTheProjectOneInTheSandbox() {
        let pending = RequestCenter.Pending(request: Self.network("p1", "api.example.com"), risk: Risk(level: .rete), since: .now)
        #expect(pending.allowsSessionRule)
        #expect(pending.projectRule == nil)
        #expect(pending.projectDomain == .domain("api.example.com"))
        #expect(PermissionNotice(pending).offersAllowOnce)
        #expect(PermissionNotice(pending).body == "api.example.com")
    }

    @Test func perQuestaSessioneAllowsTheSameHostAgainOnly() {
        var center = RequestCenter()
        _ = center.receive(Self.network("1", "api.example.com"), in: session, risk: Risk(level: .rete))
        #expect(center.answer("1", in: session, with: .allowForSession) == true)
        #expect(center.receive(Self.network("2", "API.example.com"), in: session, risk: Risk(level: .rete)) == .allowed)
        #expect(center.receive(Self.network("3", "other.example.com"), in: session, risk: Risk(level: .rete)) == .queued)
    }

    @Test func aLastingAnswerSaysSoAndNothingElseChanges() throws {
        #expect(String(decoding: try BridgeCommand.answerPermission(request: "p1", allows: true, isLasting: true).line(), as: UTF8.self)
            == #"{"behavior":"allow","request":"p1","scope":"session","type":"permission","v":4}"# + "\n")
        #expect(String(decoding: try BridgeCommand.answerPermission(request: "p1", allows: false, isLasting: true).line(), as: UTF8.self)
            == #"{"behavior":"deny","request":"p1","type":"permission","v":4}"# + "\n")
    }

    // MARK: Regole che allargano la Sandbox

    @Test func theWideningRulesTravelAsJSON() throws {
        let command = String(decoding: try BridgeCommand.readSandboxRules(id: "r1", directory: URL(filePath: "/tmp/wt"),
                                                                           settingSources: ["user"]).line(), as: UTF8.self)
        #expect(command == #"{"cwd":"/tmp/wt","id":"r1","settingSources":["user"],"type":"sandboxRules","v":4}"# + "\n")
        let line = #"{"v":4,"type":"sandboxRules","id":"r1","rules":[{"rule":"Edit(~/altro/**)","source":"userSettings"}]}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8))
            == .sandboxRules(id: "r1", [SandboxWideningRule(rule: "Edit(~/altro/**)", source: "userSettings")]))
        #expect(SandboxWideningRule(rule: "x", source: "userSettings").sourceTitle == String(localized: "Le tue impostazioni"))
        #expect(SandboxWideningRule(rule: "x", source: "cliArg").sourceTitle == "cliArg")
    }

    // MARK: Sessione

    /// A bridge played by `/bin/sh` that writes every command to `log`. Its first turn asks for `api.example.com`
    /// and, once answered, reports a blocked write; every later turn just ends.
    static func networkBridge(log: URL) -> AgentBridge {
        let script = #"""
            turn=0
            while read line; do
                echo "$line" >> "$1"
                case "$line" in
                    *'"type":"ask"'*)
                        turn=$((turn + 1))
                        id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                        if [ "$turn" = 1 ]; then
                            echo "{\"v\":4,\"type\":\"permission\",\"id\":\"$id\",\"request\":\"n1\",\"tool\":\"SandboxNetworkAccess\",\"host\":\"api.example.com\"}"
                        else
                            echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
                        fi ;;
                    *'"request":"n1"'*)
                        echo "{\"v\":4,\"type\":\"sandboxBlock\",\"id\":\"$id\",\"kind\":\"write\",\"target\":\"/Users/u/.cache/tool/a.txt\"}"
                        echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
                esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", log.path],
                           environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/u"]) { _, _ in "" }
    }

    // Criteri di accettazione: "Sempre in questo Progetto" su un dominio → la Sessione successiva lo ha tra i domini
    // della Sandbox, quindi 0 Richieste per quell'host; 0 scritture nei settings del Progetto.
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func sempreInQuestoProgettoReachesTheNextTurnsSandboxAndNoSettings() async throws {
        let repos = try WorktreeManagerTests()
        let repo = try repos.makeRepo("repo", files: ["README.md": "ciao"])
        let log = repos.base.appending(path: "bridge.log")
        let file = repos.base.appending(path: "Sessioni.json")
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let (defaults, suite) = try Self.defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let sandbox = SandboxStore(defaults: defaults)
        sandbox.setEnabled(true, in: repo)
        let bridge = Self.networkBridge(log: log)
        let store = SessionStore(file: file, worktrees: repos.manager, sandbox: sandbox) { bridge }

        try store.start("Scarica", title: "Prova", branch: "bubo/prova", in: repo)
        try await SessionTests.wait { store.permissions.queues.values.first?.first != nil }
        let id = try #require(store.sessions.first?.id)
        let pending = try #require(store.permissions.queues[id]?.first)
        #expect(pending.request.host == "api.example.com")
        store.allowDomainInProject(pending.id, in: id)
        try await SessionTests.wait { store.sessions.first?.activity == .ferma }
        #expect(store.sandboxBlocks[id] == [SandboxBlock(kind: .write, target: "/Users/u/.cache/tool/a.txt")])

        store.sendBack("Ancora", to: id, keepingAcceptedAmong: [])
        try await SessionTests.wait {
            (try? String(contentsOf: log, encoding: .utf8))?.split(separator: "\n").filter { $0.contains(#""type":"ask""#) }.count == 2
        }
        try await SessionTests.wait { store.sessions.first?.activity == .ferma }

        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        #expect(lines.contains { $0.contains(#""request":"n1""#) && $0.contains(#""scope":"session""#) && $0.contains(#""behavior":"allow""#) })
        let asks = lines.filter { $0.contains(#""type":"ask""#) }
        let first = try #require(try JSONSerialization.jsonObject(with: Data(asks[0].utf8)) as? [String: Any])
        let second = try #require(try JSONSerialization.jsonObject(with: Data(asks[1].utf8)) as? [String: Any])
        func domains(_ ask: [String: Any]) -> [String] {
            ((ask["sandbox"] as? [String: Any])?["network"] as? [String: Any])?["allowedDomains"] as? [String] ?? []
        }
        #expect(!domains(first).contains("api.example.com"))
        #expect(domains(second).contains("api.example.com"))
        // The new turn starts with no block of the one before.
        #expect(store.sandboxBlocks[id] == nil)
        let workspace = try #require(store.sessions.first?.workspace?.folder)
        for folder in [repo, workspace] {
            for name in ["settings.json", "settings.local.json"] {
                #expect(!FileManager.default.fileExists(atPath: folder.appending(path: ".claude/\(name)").path))
            }
        }
    }
}
