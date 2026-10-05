import Foundation
import Synchronization
import Testing
@testable import Bubo

/// A Sessione on Copilot does without the parts that exist only with Claude, and never calls `claude` (ADR 0012).
/// The bridge and `copilot` are fakes: no paid turn.
@MainActor
struct CopilotSessionTests {
    /// A bridge played by `/bin/sh` that writes every command to `$1` and keeps each turn going until it is cancelled.
    static func bridge(log: URL, hasClaude: Bool = true) -> AgentBridge {
        let script = #"""
            while read line; do
                echo "$line" >> "$1"
                id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                case "$line" in
                    *'"type":"copilot"'*|*'"type":"ask"'*) turn=$id ;;
                    *'"type":"cancel"'*) echo "{\"v\":4,\"type\":\"done\",\"id\":\"$turn\"}" ;;
                esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", log.path],
                           environment: ["PATH": "/usr/bin:/bin"], hasClaude: hasClaude) { _, _, _ in "" }
    }

    // #719: with only `copilot` a Sessione on Copilot starts, and one on Claude keeps today's error and remedy.
    @Test func withOnlyCopilotACopilotSessioneStartsAndAClaudeOneSaysClaudeIsMissing() async throws {
        let log = URL.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).log")
        let file = URL.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        let project = URL(filePath: "/tmp")
        func interrupted(on engine: Session.Engine) -> Session {
            var session = Session(id: UUID(), title: "Prova", project: project, activitySince: .now)
            session.engine = engine
            session.prompt = "Lavora"
            session.isInterrupted = true
            session.isOnCheckout = true
            session.workspace = Workspace(folder: project)
            return session
        }
        let copilot = interrupted(on: .copilot), claude = interrupted(on: .claude)
        try JSONEncoder().encode([copilot, claude]).write(to: file)
        let bridge = Self.bridge(log: log, hasClaude: false)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: URL.temporaryDirectory)) { bridge }
        store.locateCopilot = { URL(filePath: "/c") }
        store.copilotConsents = { [EndpointSettings.copilotConsentID] }

        store.resume(copilot.id)
        store.resume(claude.id)
        try await waitForCondition { (try? String(contentsOf: log, encoding: .utf8))?.contains(#""type":"copilot""#) == true }
        try await waitForCondition { store.sessions.first { $0.id == claude.id }?.failure != nil }

        #expect(store.sessions.first { $0.id == claude.id }?.failure
                == String(localized: "Claude Code non trovato: installa la CLI claude."))
        store.interrupt(copilot.id)
        try await waitForCondition { store.sessions.first { $0.id == copilot.id }?.isRunning == false }
        #expect(store.sessions.first { $0.id == copilot.id }?.failure == nil)
        #expect(try !String(contentsOf: log, encoding: .utf8).contains(#""type":"ask""#))
    }

    @Test func aCopilotTurnNeverCallsClaudeNorHasItsSandboxAndPlugins() async throws {
        let log = URL.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).log")
        let file = URL.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        let suite = "CopilotSessionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
            defaults.removePersistentDomain(forName: suite)
        }
        let project = URL(filePath: "/tmp")
        var saved = Session(id: UUID(), title: "Prova", project: project, activitySince: .now)
        saved.engine = .copilot
        saved.prompt = "Lavora"
        saved.isInterrupted = true
        saved.isOnCheckout = true
        saved.workspace = Workspace(folder: project)
        try JSONEncoder().encode([saved]).write(to: file)
        let sandbox = SandboxStore(defaults: defaults)
        sandbox.setEnabled(true, in: project)
        let bridge = Self.bridge(log: log)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: URL.temporaryDirectory),
                                 sandbox: sandbox) { bridge }
        let askedClaude = Mutex(false)
        store.outdatedClaude = {
            askedClaude.withLock { $0 = true }
            return nil
        }
        store.locateCopilot = { URL(filePath: "/c") }
        store.copilotConsents = { [EndpointSettings.copilotConsentID] }

        store.resume(saved.id)
        try await waitForCondition { (try? String(contentsOf: log, encoding: .utf8))?.contains(#""type":"copilot""#) == true }
        #expect(store.sandboxedTurns[saved.id] == false)
        // A change of the plugins leaves the turn alone: `copilot` does not load them.
        store.pluginReloader.pluginsDidChange()
        #expect(store.pluginReloader.state(of: saved.id) == nil)

        store.interrupt(saved.id)
        try await waitForCondition { store.sessions.first?.isRunning == false }
        let commands = try String(contentsOf: log, encoding: .utf8)
        #expect(!commands.contains(#""type":"ask""#))
        #expect(!askedClaude.withLock { $0 })
    }
}
