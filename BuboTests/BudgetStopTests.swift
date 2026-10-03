import Foundation
import Testing
@testable import Bubo

/// #165 and #492: the soft stop at 100% of a Budget in the Sessioni, with a bridge played by `/bin/sh`.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BudgetStopTests {
    let log = FileManager.default.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).log")
    let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
    let budgets = BudgetSettings(defaults: UserDefaults(suiteName: "BudgetStopTests-\(UUID().uuidString)")!)
    let ledger = CostLedger()

    /// A bridge that writes each command to `log` and answers by the prompt: «Lunga» never ends, «Spendi» costs $1.50
    /// with the API key, «Stima» reports one output token of Sonnet and never ends, «Chiudi» reports the same token
    /// and then a figure of $0.10, any other ends at its cap when it has one, and else answers.
    func bridge(withAPIKey: Bool = true) -> AgentBridge {
        let script = #"""
            while read -r line; do
              echo "$line" >> "$LOG"
              case "$line" in *'"type":"ask"'*) ;; *) continue ;; esac
              id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
              case "$line" in
                *'"prompt":"Lunga"'*) ;;
                *'"prompt":"Stima"'*|*'"prompt":"Chiudi"'*)
                  echo "{\"v\":4,\"type\":\"estimate\",\"id\":\"$id\",\"mode\":\"apiKey\",\"basis\":\"list\",\"complete\":false,\"models\":[{\"model\":\"claude-sonnet-4-5-20250929\",\"inputTokens\":0,\"outputTokens\":1,\"cacheReadTokens\":0,\"cacheWriteTokens\":0,\"thinkingTokens\":0}]}"
                  case "$line" in *'"prompt":"Chiudi"'*)
                    echo "{\"v\":4,\"type\":\"usage\",\"id\":\"$id\",\"mode\":\"apiKey\",\"cost\":0.1,\"basis\":\"list\",\"complete\":true,\"models\":[]}"
                    echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
                  esac ;;
                *'"prompt":"Spendi"'*)
                  echo "{\"v\":4,\"type\":\"usage\",\"id\":\"$id\",\"mode\":\"apiKey\",\"cost\":1.5,\"basis\":\"list\",\"complete\":true,\"models\":[]}"
                  echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
                *'"maxBudget"'*) echo "{\"v\":4,\"type\":\"budgetExhausted\",\"id\":\"$id\"}" ;;
                *) echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
              esac
            done
            """#
        var environment = ["PATH": "/usr/bin:/bin", "LOG": log.path]
        if withAPIKey { environment["ANTHROPIC_API_KEY"] = "sk-ant-prova" }
        return AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script],
                           environment: environment) { _, _, _ in "" }
    }

    func store(_ bridge: AgentBridge) -> SessionStore {
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory),
                                 ledger: ledger) { bridge }
        store.budgets = budgets
        // One output token of Sonnet costs $0.60.
        store.prices = AnthropicPriceTable(date: .now, models: ["claude-sonnet-4-5": .init(
            input: 0, output: 600_000, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)])
        return store
    }

    /// The `ask` commands the bridge received, in order.
    func asks() -> [String] {
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init).filter { $0.contains(#""type":"ask""#) }
    }

    func spend(_ cost: Decimal) {
        ledger.record(TurnUsage(mode: .apiKey, cost: cost, basis: .list, isComplete: true, models: []),
                      turn: UUID().uuidString, question: UUID(), provider: Budgets.claude)
    }

    func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "progetto-\(UUID().uuidString)",
                                                                      directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aSpentBudgetSendsNothingAndWaitsForTheUser() async throws {
        defer { try? FileManager.default.removeItem(at: file) }
        spend(2)
        budgets.budgets.providers[Budgets.claude] = 2
        let store = store(bridge())

        try store.start("Ciao", title: "Prova", branch: "", in: try folder(), onCheckout: true)
        try await SessionTests.wait { store.sessions.first?.budgetStop != nil }

        let session = try #require(store.sessions.first)
        #expect(session.budgetStop == .provider(Budgets.claude))
        #expect(session.activity == .ferma)
        #expect(session.unstartedPrompt == "Ciao")
        #expect(asks().isEmpty)
    }

    // Spec 18: each turn gets the shared residue as `maxBudgetUsd`; past it, only the user's choice goes on.
    @Test func aTurnStopsAtTheResidueAndContinuesOnlyOnceConfirmed() async throws {
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        spend(2)
        budgets.budgets.providers[Budgets.claude] = 5
        let store = store(bridge())

        let id = try store.start("Tetto", title: "Prova", branch: "", in: try folder(), onCheckout: true)
        try await SessionTests.wait { store.sessions.first?.budgetStop != nil }
        #expect(asks().count == 1)
        #expect(asks().first?.contains(#""maxBudget":3"#) == true)

        store.resumeAfterBudget(id, ignoringBudget: true)
        try await SessionTests.wait { store.sessions.first?.activity == .ferma && store.sessions.first?.budgetStop == nil }

        #expect(asks().count == 2)
        #expect(asks().last?.contains("maxBudget") == false)
        #expect(store.sessions.first?.unstartedPrompt == nil)
    }

    @Test func withTheSubscriptionNoBudgetCaps() async throws {
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        spend(2)
        budgets.budgets.providers[Budgets.claude] = 2
        let store = store(bridge(withAPIKey: false))

        try store.start("Ciao", title: "Prova", branch: "", in: try folder(), onCheckout: true)
        try await SessionTests.wait { !asks().isEmpty && store.sessions.first?.activity == .ferma }

        #expect(store.sessions.first?.budgetStop == nil)
        #expect(asks().first?.contains("maxBudget") == false)
    }

    // Acceptance of #165: two Sessioni on the same Budget; once one spends it, the other stops at once.
    @Test func whenOneSessionSpendsTheBudgetTheOtherStops() async throws {
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        budgets.budgets.providers[Budgets.claude] = 1
        let store = store(bridge())

        let long = try store.start("Lunga", title: "Lunga", branch: "", in: try folder(), onCheckout: true)
        try await SessionTests.wait { asks().count == 1 }
        let spending = try store.start("Spendi", title: "Spendi", branch: "", in: try folder(), onCheckout: true)
        try await SessionTests.wait { store.sessions.first { $0.id == long }?.budgetStop != nil }

        #expect(asks().count == 2)
        #expect(asks().allSatisfy { $0.contains(#""maxBudget":1"#) })
        let stopped = try #require(store.sessions.first { $0.id == long })
        #expect(stopped.activity == .ferma)
        #expect(stopped.unstartedPrompt == "Lunga")
        try await SessionTests.wait { store.sessions.first { $0.id == spending }?.activity == .ferma }
        #expect(store.sessions.first { $0.id == spending }?.budgetStop == nil)
    }

    // Acceptance of #492: two long turns on the same Budget; once their estimates reach it, both stop.
    @Test func whenTheEstimatesReachTheBudgetBothSessionsStop() async throws {
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        budgets.budgets.providers[Budgets.claude] = 1
        let store = store(bridge())

        let first = try store.start("Stima", title: "Prima", branch: "", in: try folder(), onCheckout: true)
        try await SessionTests.wait { asks().count == 1 }
        // $0.60 of $1: the first goes on alone.
        #expect(store.sessions.first { $0.id == first }?.budgetStop == nil)
        let second = try store.start("Stima", title: "Seconda", branch: "", in: try folder(), onCheckout: true)
        try await SessionTests.wait { store.sessions.allSatisfy { $0.budgetStop != nil } }

        #expect(Set(store.sessions.map(\.id)) == [first, second])
        #expect(store.sessions.allSatisfy { $0.activity == .ferma && $0.unstartedPrompt == "Stima" })
        // No `result` came: each turn keeps its estimate, marked incomplete.
        try await SessionTests.wait { ledger.entries.count == 2 }
        #expect(ledger.entries.allSatisfy { $0.usage.cost == Decimal(string: "0.6") && !$0.usage.isComplete })
        #expect(ledger.entries.allSatisfy { $0.usage.origin == .priceTable })
    }

    @Test func theLedgerKeepsOnlyTheFigureOfTheResult() async throws {
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: file)
        }
        budgets.budgets.providers[Budgets.claude] = 5
        let store = store(bridge())

        try store.start("Chiudi", title: "Prova", branch: "", in: try folder(), onCheckout: true)
        try await SessionTests.wait { ledger.entries.first?.usage.isComplete == true }
        try await SessionTests.wait { store.sessions.first?.activity == .ferma }

        #expect(ledger.entries.count == 1)
        let entry = try #require(ledger.entries.first)
        #expect(entry.usage.cost == Decimal(string: "0.1"))
        #expect(entry.usage.isComplete)
        #expect(entry.usage.origin == .listEstimate)
    }
}
