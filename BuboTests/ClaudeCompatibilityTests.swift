import Foundation
import Testing
@testable import Bubo

/// The minimum version of `claude` and its capabilities (spec 27): the table of versions, the file shared with the
/// bridge, and the bridge's events.
struct ClaudeCompatibilityTests {
    let compatibility = ClaudeCompatibility(minimumVersion: ClaudeVersion(major: 2, minor: 1, patch: 275))

    @Test(arguments: [
        // Below.
        ("2.1.274", true), ("2.0.999", true), ("1.9.300", true), ("2.1.275-beta.1", true), ("2.1", true),
        // Equal.
        ("2.1.275", false), ("2.1.275 (Claude Code)", false), ("v2.1.275", false),
        // Above.
        ("2.1.276", false), ("2.2.0", false), ("3.0", false), ("10.0.0", false), ("2.1.286.1", false),
        // Formats Bubo cannot read: never outdated, with no maximum.
        ("", false), ("abc", false), ("Claude Code", false), ("..", false),
    ])
    func eachVersionHasItsOutcome(version: String, isOutdated: Bool) {
        #expect(compatibility.isOutdated(version) == isOutdated)
    }

    @Test func theBundleHasTheMinimumOfTheBridge() throws {
        let source = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "bridge/compat.json")
        #expect(ClaudeCompatibility.bundled == ClaudeCompatibility(file: source))
        #expect(ClaudeCompatibility.bundled.minimumVersion == ClaudeVersion(major: 2, minor: 1, patch: 275))
    }

    @Test func withoutTheFileNothingIsOutdated() {
        let missing = ClaudeCompatibility(file: URL(filePath: "/tmp/bubo-compat-\(UUID().uuidString).json"))
        #expect(!missing.isOutdated("0.0.1"))
    }

    @Test func unknownCapabilitiesAreLeftOutAndMissingOnesAreNone() {
        #expect(ClaudeCapability.known(in: ["interrupt_receipt_v1", "nuova_v9"]) == [.interruptReceipt])
        #expect(ClaudeCapability.known(in: []).isEmpty)
        #expect(ClaudeCapability.known(in: nil).isEmpty)
    }

    @Test func theBridgeReportsClaudeAndAnOutdatedOne() throws {
        let decoder = JSONDecoder()
        let claude = #"{"v":4,"type":"claude","id":"a","version":"2.1.286","capabilities":["queued_notifications","x"]}"#
        #expect(try decoder.decode(BridgeEvent.self, from: Data(claude.utf8))
            == .claude(id: "a", version: "2.1.286", capabilities: [.queuedNotifications]))
        let old = #"{"v":4,"type":"claude","id":"a","version":"2.1.100"}"#
        #expect(try decoder.decode(BridgeEvent.self, from: Data(old.utf8)) == .claude(id: "a", version: "2.1.100", capabilities: []))
        let outdated = #"{"v":4,"type":"outdated","id":"a","version":"2.1.100"}"#
        #expect(try decoder.decode(BridgeEvent.self, from: Data(outdated.utf8)) == .outdated(id: "a", version: "2.1.100"))
        let refused = #"{"v":4,"type":"outdated","id":"a"}"#
        #expect(try decoder.decode(BridgeEvent.self, from: Data(refused.utf8)) == .outdated(id: "a", version: nil))
    }

    /// A bridge played by `/bin/sh` that writes every command to `log`: the `claude` of the first `oldTurns` turns
    /// is 2.1.200, too old, the next ones are 2.1.286 and end at once.
    static func agingBridge(log: URL, oldTurns: Int = 1) -> AgentBridge {
        let script = #"""
            turns=0
            while read line; do
                echo "$line" >> "$1"
                id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
                case "$line" in
                    *'"type":"ask"'*)
                        turns=$((turns + 1))
                        if [ $turns -le "$2" ]; then
                            echo "{\"v\":4,\"type\":\"claude\",\"id\":\"$id\",\"version\":\"2.1.200\"}"
                            echo "{\"v\":4,\"type\":\"outdated\",\"id\":\"$id\",\"version\":\"2.1.200\"}"
                        else
                            echo "{\"v\":4,\"type\":\"claude\",\"id\":\"$id\",\"version\":\"2.1.286\",\"capabilities\":[\"interrupt_receipt_v1\"]}"
                            echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
                        fi ;;
                esac
            done
            """#
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script, "sh", log.path, String(oldTurns)],
                           environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/u"]) { _, _, _ in "" }
    }

    /// The `ask` lines the bridge received.
    static func asks(in log: URL) -> [Substring] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").filter { $0.contains(#""type":"ask""#) }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func aClaudeTooOldAtInitHoldsTheTurnUntilItIsUpdated() async throws {
        let temporary = FileManager.default.temporaryDirectory
        let log = temporary.appending(path: "bridge-\(UUID().uuidString).log")
        let file = temporary.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        let bridge = Self.agingBridge(log: log)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: temporary)) { bridge }
        var reported: [String?] = []
        store.onClaudeOutdated = { reported.append($0) }

        try store.start("Scrivi i test", title: "Prova", branch: "", in: URL(filePath: "/tmp"), onCheckout: true)
        try await SessionTests.wait { store.sessions.first?.activity == .errore }
        let held = try #require(store.sessions.first)
        #expect(held.unstartedPrompt == "Scrivi i test")
        #expect(held.failure == String(localized: "Claude Code \("2.1.200") è troppo vecchio per Bubo. Aggiornalo e la Sessione parte da sola."))
        #expect(store.awaitingClaudeUpdate == [held.id])
        #expect(reported == ["2.1.200"])
        #expect(bridge.claude?.version == "2.1.200")

        store.startTurnsAwaitingUpdate()
        try await SessionTests.wait { store.sessions.first?.activity == .ferma }
        #expect(store.sessions.first?.activity == .ferma)
        #expect(store.awaitingClaudeUpdate.isEmpty)
        #expect(Self.asks(in: log).count == 2)
        #expect(bridge.claude?.version == "2.1.286")
        #expect(bridge.claude?.capabilities == [.interruptReceipt])
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func aClaudeTooOldBeforeThePromptStartsNothing() async throws {
        let temporary = FileManager.default.temporaryDirectory
        let log = temporary.appending(path: "bridge-\(UUID().uuidString).log")
        let file = temporary.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        let bridge = Self.agingBridge(log: log, oldTurns: 0)
        var asked = 0
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: temporary)) {
            asked += 1
            return bridge
        }
        store.outdatedClaude = { "2.1.274" }

        try store.start("Scrivi i test", title: "Prova", branch: "", in: URL(filePath: "/tmp"), onCheckout: true)
        try await SessionTests.wait { store.sessions.first?.activity == .errore }

        #expect(store.sessions.first?.activity == .errore)
        #expect(asked == 0)
        #expect(Self.asks(in: log).isEmpty)
    }
}
