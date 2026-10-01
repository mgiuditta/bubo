import Foundation
import Testing
@testable import Bubo

/// The gate of spec 22 on Bubo's side: the Modalità autonoma, the Livello di rischio the bridge's gate asks for, and
/// the Richieste "Fuori dalla Sandbox". The gate itself is tested in `bridge/src/gate.test.ts`.
struct SandboxGateTests {
    let session = UUID()

    static func outside(_ id: String, _ command: String) -> PermissionRequest {
        var request = PermissionRequest(id: id, tool: "Bash", command: command)
        request.isOutsideSandbox = true
        return request
    }

    @Test func theSandboxNoLongerAsksForEverySandboxedCommand() {
        let object = SandboxTests.policy().jsonObject
        #expect(object["autoAllowBashIfSandboxed"] as? Bool == true)
        #expect(object["allowUnsandboxedCommands"] as? Bool == true)
    }

    @Test func askCarriesThePermissionModeOnlyWhenGiven() throws {
        let autonomous = try BridgeCommand.ask(id: "a1", prompt: "x", directory: URL(filePath: "/tmp"), settingSources: [],
                                               permissionMode: .autonomous).line()
        #expect(String(decoding: autonomous, as: UTF8.self).contains(#""permissionMode":"auto""#))
        let manual = try BridgeCommand.ask(id: "a1", prompt: "x", directory: URL(filePath: "/tmp"), settingSources: [],
                                           permissionMode: .manual).line()
        #expect(String(decoding: manual, as: UTF8.self).contains(#""permissionMode":"default""#))
        let unsaid = try BridgeCommand.ask(id: "a1", prompt: "x", directory: URL(filePath: "/tmp"), settingSources: []).line()
        #expect(!String(decoding: unsaid, as: UTF8.self).contains("permissionMode"))
    }

    @Test func theGateQuestionAndItsAnswerTravelAsJSON() throws {
        let line = #"{"v":4,"type":"risk","id":"a1","request":"r1","tool":"Bash","command":"rm -rf build"}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8))
            == .risk(id: "a1", PermissionRequest(id: "r1", tool: "Bash", command: "rm -rf build")))
        #expect(String(decoding: try BridgeCommand.answerRisk(request: "r1", isDangerous: true).line(), as: UTF8.self)
            == #"{"dangerous":true,"request":"r1","type":"risk","v":4}"# + "\n")
    }

    @Test func aRequestOutsideTheSandboxIsMarked() throws {
        let line = #"{"v":4,"type":"permission","id":"a1","request":"p1","tool":"Bash","command":"npm i","outsideSandbox":true}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .permission(id: "a1", Self.outside("p1", "npm i")))
    }

    // Criterio di accettazione: 0 ritentativi fuori sandbox approvati senza Richiesta.
    @Test func outsideTheSandboxOnlyNoAndSoloOraAndNothingAllowsItAgain() {
        var center = RequestCenter()
        _ = center.receive(PermissionRequest(id: "1", tool: "Bash", command: "npm i"), in: session, risk: Risk(level: .modifica))
        #expect(center.answer("1", in: session, with: .allowForSession) == true)

        #expect(center.receive(Self.outside("2", "npm i"), in: session, risk: Risk(level: .modifica)) == .queued)
        let pending = center.queues[session]?.first
        #expect(pending?.allowsSessionRule == false)
        #expect(pending?.projectRule == nil)
        #expect(center.answer("2", in: session, with: .allowForSession) == true)
        #expect(center.receive(Self.outside("3", "npm i"), in: session, risk: Risk(level: .modifica)) == .queued)
    }

    @Test func itsNotificationNeverApproves() {
        let notice = PermissionNotice(RequestCenter.Pending(request: Self.outside("1", "npm i"), risk: Risk(level: .modifica),
                                                            since: .now))
        #expect(!notice.offersAllowOnce)
    }

    @Test func theModalitaAutonomaIsPossibleOnlyInTheSessionesOwnWorktree() {
        var session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp/repo"))
        session.isAutonomous = true
        #expect(session.permissionMode == .manual)
        session.workspace = Workspace(folder: URL(filePath: "/tmp/wt"), branch: "bubo/prova")
        #expect(session.allowsAutonomy)
        #expect(session.permissionMode == .autonomous)
        session.workspace = Workspace(folder: URL(filePath: "/tmp/repo"))
        #expect(session.permissionMode == .manual)
        session.workspace = Workspace(folder: URL(filePath: "/tmp/repo"), branch: "main")
        session.isOnCheckout = true
        #expect(!session.allowsAutonomy)
        #expect(session.permissionMode == .manual)
    }

    @Test func aSessioneSavedBeforeTheModalitaAutonomaIsManual() throws {
        let saved = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Vecchia","project":"file:///tmp/repo","activity":"ferma"}"#
        #expect(try !JSONDecoder().decode(Session.self, from: Data(saved.utf8)).isAutonomous)
    }

    /// A bridge played by `/bin/sh` that writes every command to `log`: each turn asks the gate about a destructive
    /// command, then about a reading one, and ends once both are answered.
    static func gateBridge(log: URL) -> AgentBridge {
        let script = #"""
            while read line; do
                echo "$line" >> "$1"
                case "$line" in
                    *'"type":"ask"'*)
                        id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                        echo "{\"v\":4,\"type\":\"risk\",\"id\":\"$id\",\"request\":\"r1\",\"tool\":\"Bash\",\"command\":\"rm -rf build\"}"
                        echo "{\"v\":4,\"type\":\"risk\",\"id\":\"$id\",\"request\":\"r2\",\"tool\":\"Bash\",\"command\":\"ls\"}" ;;
                    *'"request":"r2"'*) echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
                esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", log.path],
                           environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/u"]) { _, _ in "" }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func theGateGetsTheRiskAndTheNextTurnRunsInTheModalitaAutonoma() async throws {
        let repos = try WorktreeManagerTests()
        let repo = try repos.makeRepo("repo", files: ["README.md": "ciao"])
        let log = repos.base.appending(path: "bridge.log")
        let file = repos.base.appending(path: "Sessioni.json")
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let suite = "SandboxGateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bridge = Self.gateBridge(log: log)
        let store = SessionStore(file: file, worktrees: repos.manager, sandbox: SandboxStore(defaults: defaults)) { bridge }

        try store.start("Pulisci", title: "Prova", branch: "bubo/prova", in: repo)
        try await SessionTests.wait { store.sessions.first?.activity == .ferma }
        let id = try #require(store.sessions.first?.id)
        store.setAutonomous(true, in: id)
        #expect(store.sessions.first?.isAutonomous == true)
        store.sendBack("Ancora", to: id, keepingAcceptedAmong: [])
        try await SessionTests.wait { store.sessions.first?.activity == .ferma && store.sessions.first?.summary == nil }
        try await SessionTests.wait {
            (try? String(contentsOf: log, encoding: .utf8))?.split(separator: "\n").filter { $0.contains(#""type":"risk""#) }.count == 4
        }

        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        let asks = lines.filter { $0.contains(#""type":"ask""#) }
        #expect(asks.count == 2)
        #expect(asks.first?.contains(#""permissionMode":"default""#) == true)
        #expect(asks.last?.contains(#""permissionMode":"auto""#) == true)
        let answers = lines.filter { $0.contains(#""type":"risk""#) }
        #expect(answers.count == 4)
        #expect(answers.filter { $0.contains(#""request":"r1""#) }.allSatisfy { $0.contains(#""dangerous":true"#) })
        #expect(answers.filter { $0.contains(#""request":"r2""#) }.allSatisfy { $0.contains(#""dangerous":false"#) })
    }

    @MainActor
    @Test func theModalitaAutonomaCannotBeTurnedOnOnTheCheckout() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            throw AgentBridgeError.failed(message: "nessun ponte")
        }
        try store.start("x", title: "Prova", branch: "", in: URL(filePath: "/tmp"), onCheckout: true)
        let id = try #require(store.sessions.first?.id)
        store.setAutonomous(true, in: id)
        #expect(store.sessions.first?.isAutonomous == false)
    }
}
