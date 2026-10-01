import Foundation
import Testing
@testable import Bubo

@MainActor
struct CostLedgerTests {
    static let project = URL(filePath: "/tmp/progetto")

    static func usage(_ mode: TurnUsage.Mode, _ cost: Decimal?, basis: TurnUsage.Basis = .list,
                      isComplete: Bool = true) -> TurnUsage {
        TurnUsage(mode: mode, cost: cost, basis: basis, isComplete: isComplete, models: [
            .init(model: "claude-sonnet-4-5", inputTokens: 100, outputTokens: 10, cacheReadTokens: 5, cacheWriteTokens: 1,
                  thinkingTokens: 2, cost: cost),
        ])
    }

    @Test func aTurnReadAgainReplacesItsEntry() {
        let ledger = CostLedger()
        let session = UUID()
        ledger.record(Self.usage(.apiKey, 0.1), turn: "t1", session: session, project: Self.project)
        ledger.record(Self.usage(.apiKey, 0.35), turn: "t1", session: session, project: Self.project)
        ledger.record(Self.usage(.apiKey, 0.2), turn: "t2", session: session, project: Self.project)
        #expect(ledger.entries.map(\.id) == ["t1", "t2"])
        #expect(ledger.total(of: session) == [.spesa: .init(value: 0.35 + 0.2)])
    }

    @Test func theHistoryAddsUpToTheFinalTotalsExactly() throws {
        let ledger = CostLedger()
        let session = UUID()
        // The figures as the bridge sends them, read the way BridgeEvent reads them.
        let finals = ["0.35", "0.27", "0.5", "0.12", "0.0001234567"]
        for (index, cost) in finals.enumerated() {
            for partial in ["0.01", cost] {
                let line = #"{"mode":"apiKey","cost":\#(partial),"basis":"list","complete":true,"models":[]}"#
                let usage = try JSONDecoder().decode(TurnUsage.self, from: Data(line.utf8))
                ledger.record(usage, turn: "t\(index)", session: session, project: Self.project)
            }
        }
        let expected = finals.map { Decimal(string: $0)! }.reduce(0, +)
        #expect(ledger.total(of: session)[.spesa]?.value == expected)
    }

    @Test func aSessionMovedToTheAPIKeyKeepsBothUnitsApart() {
        let ledger = CostLedger()
        let session = UUID()
        ledger.record(Self.usage(.subscription, 1.2), turn: "t1", session: session, project: Self.project)
        ledger.record(Self.usage(.apiKey, 0.3), turn: "t2", session: session, project: Self.project)
        #expect(ledger.total(of: session) == [.valoreListino: .init(value: 1.2), .spesa: .init(value: 0.3)])
        #expect(ledger.lastTurn(of: session)?.usage.unit == .spesa)
    }

    @Test func anUnknownBasisIsUncertainAndACrashIsIncomplete() {
        let ledger = CostLedger()
        let session = UUID()
        ledger.record(Self.usage(.apiKey, 0.3, basis: .unknown), turn: "t1", session: session, project: Self.project)
        ledger.record(Self.usage(.apiKey, nil, isComplete: false), turn: "t2", session: session, project: Self.project)
        #expect(ledger.total(of: session) == [.spesa: .init(value: 0.3, isUncertain: true, isIncomplete: true)])
    }

    @Test func otherSessionsDoNotCount() {
        let ledger = CostLedger()
        ledger.record(Self.usage(.apiKey, 0.3), turn: "t1", session: UUID(), project: Self.project)
        #expect(ledger.total(of: UUID()).isEmpty)
    }

    @Test func theLedgerIsKeptAcrossLaunches() {
        let file = FileManager.default.temporaryDirectory.appending(path: "Costi-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let session = UUID()
        CostLedger(file: file).record(Self.usage(.subscription, 0.42), turn: "t1", session: session, project: Self.project)
        let reopened = CostLedger(file: file)
        #expect(reopened.entries.map(\.usage) == [Self.usage(.subscription, 0.42)])
        #expect(reopened.total(of: session) == [.valoreListino: .init(value: 0.42)])
    }

    @Test func aUsageEventIsReadWithItsTokens() throws {
        let line = #"{"v":3,"type":"usage","id":"a1","mode":"subscription","cost":0.075,"basis":"unknown","complete":true,"models":[{"model":"claude-sonnet-4-5","inputTokens":20,"outputTokens":10,"cacheReadTokens":0,"cacheWriteTokens":0,"thinkingTokens":0,"cost":0.075}]}"#
        let event = try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8))
        #expect(event == .usage(id: "a1", TurnUsage(mode: .subscription, cost: Decimal(string: "0.075"), basis: .unknown,
                                                    isComplete: true, models: [
            .init(model: "claude-sonnet-4-5", inputTokens: 20, outputTokens: 10, cacheReadTokens: 0, cacheWriteTokens: 0,
                  thinkingTokens: 0, cost: Decimal(string: "0.075")),
        ])))
    }

    @Test func aCrashedTurnHasTokensButNoFigure() throws {
        let line = #"{"mode":"apiKey","basis":"list","complete":false,"models":[{"model":"m","inputTokens":300,"outputTokens":60,"cacheReadTokens":4,"cacheWriteTokens":0,"thinkingTokens":0}]}"#
        let usage = try JSONDecoder().decode(TurnUsage.self, from: Data(line.utf8))
        #expect(usage.cost == nil)
        #expect(usage.models.first?.inputTokens == 300)
        #expect(!usage.isComplete)
    }

    @Test(.timeLimit(.minutes(1)))
    func eachTurnOfASessionIsRecordedOnceWithItsLatestFigure() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        // Streaming: two totals of the same turn, then the turn fails; the ledger keeps the latest.
        let script = #"""
            read line; id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
            echo "{\"v\":3,\"type\":\"usage\",\"id\":\"$id\",\"mode\":\"apiKey\",\"cost\":0.1,\"basis\":\"list\",\"complete\":true,\"models\":[]}"
            echo "{\"v\":3,\"type\":\"usage\",\"id\":\"$id\",\"mode\":\"apiKey\",\"cost\":0.25,\"basis\":\"list\",\"complete\":true,\"models\":[]}"
            echo "{\"v\":3,\"type\":\"error\",\"id\":\"$id\",\"message\":\"error_during_execution\"}"
            read _
            """#
        let bridge = AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script],
                                 environment: ["PATH": "/usr/bin:/bin"]) { _, _, _ in "" }
        let ledger = CostLedger()
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory),
                                 ledger: ledger) { bridge }

        try store.start("Ciao", title: "Prova", branch: "", in: URL(filePath: "/tmp"), onCheckout: true)
        try await SessionTests.wait { store.sessions.first?.activity == .errore }
        let session = try #require(store.sessions.first)
        #expect(ledger.entries.map(\.id) == session.conversations)
        #expect(ledger.total(of: session.id) == [.spesa: .init(value: 0.25)])
        #expect(ledger.entries.first?.project == URL(filePath: "/tmp"))
    }

    @Test func aFigureUnderACentIsNotShownAsZero() {
        #expect(SessionCostTotal.formatted(0) == Decimal(0).formatted(.currency(code: "USD")))
        #expect(SessionCostTotal.formatted(Decimal(string: "0.004")!) != Decimal(0).formatted(.currency(code: "USD")))
    }
}
