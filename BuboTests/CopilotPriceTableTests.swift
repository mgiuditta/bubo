import Foundation
import Testing
@testable import Bubo

/// The Copilot list prices, the Spesa of a Copilot turn and its Budget (#542).
@Suite(.timeLimit(.minutes(1)))
struct CopilotPriceTableTests {
    /// Made-up prices: tests never depend on GitHub's real ones.
    static let table = CopilotPriceTable(date: Date(timeIntervalSince1970: 1_790_000_000), models: [
        "claude-prova": .init(input: 2, cacheRead: Decimal(string: "0.2")!, cacheWrite: Decimal(string: "2.5")!, output: 10),
        "gpt-prova": .init(input: 1, cacheRead: Decimal(string: "0.1")!, cacheWrite: nil, output: 4),
    ])

    /// A turn as the bridge reports it: tokens only, input with the cache in it.
    static func reported(_ model: String, input: Int, cacheRead: Int = 0, cacheWrite: Int = 0,
                         output: Int) -> TurnUsage {
        TurnUsage(mode: .apiKey, cost: nil, basis: .unknown, isComplete: true, models: [
            .init(model: model, inputTokens: input, outputTokens: output, cacheReadTokens: cacheRead,
                  cacheWriteTokens: cacheWrite, thinkingTokens: 0, cost: nil),
        ])
    }

    @Test func aTurnIsSpesaFromItsTokensWithTheTablesDate() throws {
        let turn = Self.table.spesa(of: Self.reported("claude-prova", input: 10_000, cacheRead: 6_000,
                                                      cacheWrite: 1_000, output: 2_000))

        // 3,000 fresh at $2, 6,000 read at $0.20, 1,000 written at $2.50, 2,000 out at $10, per million.
        #expect(turn.cost == Decimal(string: "0.0297"))
        #expect(turn.unit == .spesa)
        #expect(turn.origin == .priceTable)
        #expect(turn.basis == .list)
        #expect(turn.priceDate == Self.table.date)
        #expect(turn.models.first?.inputTokens == 3_000)
        #expect(turn.models.first?.cost == turn.cost)
    }

    @Test func aCacheWriteWithoutItsOwnPriceCostsAsInput() {
        let turn = Self.table.spesa(of: Self.reported("GPT-Prova", input: 1_000, cacheWrite: 1_000, output: 0))

        #expect(turn.cost == Decimal(string: "0.001"))
    }

    @Test func aModelMissingFromTheListHasNoFigure() {
        let turn = Self.table.spesa(of: Self.reported("modello-nuovo", input: 1_000, output: 500))

        #expect(turn.origin == .unpriced)
        #expect(turn.cost == nil)
        #expect(turn.priceDate == nil)
        #expect(turn.models.first?.outputTokens == 500)
    }

    @Test func theBundledListHasItsDayAndClaudeOnCopilot() throws {
        let bundled = try #require(CopilotPriceTable.bundled)

        #expect(bundled.price(of: "claude-sonnet-5.5") != nil)
        #expect(bundled.date > Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test func theReasonLineSaysItIsAnEstimate() {
        var answer = RoutedAnswer(route: Route(family: .sonnet, model: "sonnet", effort: .medium,
                                               reason: .type(.writing, runnerUp: nil)), provider: nil)
        answer.usage = Self.table.spesa(of: Self.reported("gpt-prova", input: 1_000, output: 1_000))

        #expect(answer.cost == .copilotEstimate(Decimal(string: "0.005")!, pricesOf: Self.table.date))

        answer.usage = Self.table.spesa(of: Self.reported("modello-nuovo", input: 1_000, output: 500))
        #expect(answer.cost == .copilotTokens(1_500))
    }

    @Test func copilotsBudgetCountsOnlyCopilotsTurns() {
        let ledger = CostLedger()
        let project = URL(filePath: "/tmp/progetto", directoryHint: .isDirectory)
        ledger.record(Self.table.spesa(of: Self.reported("claude-prova", input: 0, output: 1_000_000)), turn: "a",
                      session: UUID(), project: project, provider: Budgets.copilot)
        ledger.record(TurnUsage(mode: .apiKey, cost: 5, basis: .list, isComplete: true, models: []), turn: "b",
                      session: UUID(), project: project)
        var budgets = Budgets()
        budgets.setLimit(10, of: .provider(Budgets.copilot))

        let guarded = BudgetGuard(budgets: budgets, entries: ledger.entries)

        #expect(guarded.status(of: .provider(Budgets.copilot))?.spent.value == 10)
        #expect(guarded.allowance(provider: Budgets.copilot, project: project) == .exhausted(.provider(Budgets.copilot)))
        #expect(guarded.allowance(provider: Budgets.claude, project: project) == .unlimited)
    }
}
