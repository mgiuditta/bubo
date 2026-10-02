import Foundation
import Testing
@testable import Bubo

/// #164: the monthly Budgets, their residue and their threshold.
@MainActor
struct BudgetGuardTests {
    static let project = URL(filePath: "/tmp/progetto", directoryHint: .isDirectory)
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }

    /// 15 March 2026, noon in Rome.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!

    static func entry(_ cost: Decimal?, provider: String = "OpenAI", project: URL? = nil,
                      mode: TurnUsage.Mode = .apiKey, origin: CostOrigin = .priceTable,
                      basis: TurnUsage.Basis = .list, at date: Date = now) -> CostLedger.Entry {
        CostLedger.Entry(id: UUID().uuidString, session: UUID(), project: project, provider: provider, date: date,
                         usage: TurnUsage(mode: mode, cost: cost, basis: basis, isComplete: true, models: [],
                                          origin: origin))
    }

    static func budgets(_ change: (inout Budgets) -> Void) -> Budgets {
        var budgets = Budgets()
        change(&budgets)
        return budgets
    }

    @Test func everyBudgetIsOffByDefault() {
        let budgets = BudgetGuard(budgets: Budgets(), entries: [Self.entry(100)], now: Self.now, calendar: Self.calendar)

        #expect(Budgets().threshold == 0.8)
        #expect(budgets.status(of: .provider("OpenAI")) == nil)
        #expect(budgets.status(of: .total) == nil)
        #expect(!budgets.isAvoided("OpenAI"))
    }

    @Test func onlyThisMonthsSpesaCounts() throws {
        let lastMonth = Self.calendar.date(byAdding: .month, value: -1, to: Self.now)!
        let entries = [
            Self.entry(3),
            Self.entry(5, at: lastMonth),
            Self.entry(7, provider: Budgets.claude, mode: .subscription, origin: .listEstimate),
            Self.entry(0, provider: "Ollama", origin: .free),
        ]
        let budgets = BudgetGuard(budgets: Self.budgets { $0.total = 10 }, entries: entries, now: Self.now,
                                  calendar: Self.calendar)

        let total = try #require(budgets.status(of: .total))
        #expect(total.spent.value == 3)
        #expect(total.remaining == 7)
        #expect(total.level == .below)
    }

    @Test(arguments: [(Decimal(7), BudgetGuard.Level.below), (8, .threshold), (9.5, .threshold), (10, .exhausted),
                      (12, .exhausted)])
    func theLevelFollowsTheThreshold(spent: Decimal, level: BudgetGuard.Level) throws {
        let budgets = BudgetGuard(budgets: Self.budgets { $0.providers["OpenAI"] = 10 }, entries: [Self.entry(spent)],
                                  now: Self.now, calendar: Self.calendar)

        #expect(try #require(budgets.status(of: .provider("OpenAI"))).level == level)
        #expect(budgets.isAvoided("OpenAI") == (level != .below))
    }

    @Test func theTightestBudgetWins() throws {
        let entries = [Self.entry(5), Self.entry(4, provider: "Gemini")]
        let budgets = BudgetGuard(budgets: Self.budgets { $0.providers["OpenAI"] = 100; $0.total = 10 },
                                  entries: entries, now: Self.now, calendar: Self.calendar)

        #expect(try #require(budgets.tightest(provider: "OpenAI")).scope == .total)
        // The total past its threshold avoids every paid provider, Gemini too.
        #expect(budgets.isAvoided("Gemini"))
    }

    @Test func aProgettoCountsItsSessioni() throws {
        let entries = [Self.entry(6, provider: Budgets.claude, project: Self.project, origin: .listEstimate),
                       Self.entry(6, provider: Budgets.claude, origin: .listEstimate)]
        let budgets = BudgetGuard(budgets: Self.budgets { $0.setLimit(10, of: .project(Self.project)) },
                                  entries: entries, now: Self.now, calendar: Self.calendar)

        #expect(try #require(budgets.status(of: .project(Self.project))).spent.value == 6)
        #expect(try #require(budgets.tightest(provider: Budgets.claude, project: Self.project)).scope
            == .project(Self.project))
    }

    @Test func aChangedBudgetCountsAtOnce() throws {
        var settings = Self.budgets { $0.providers["OpenAI"] = 10 }
        let entries = [Self.entry(9)]
        #expect(BudgetGuard(budgets: settings, entries: entries, now: Self.now, calendar: Self.calendar)
            .isAvoided("OpenAI"))

        settings.providers["OpenAI"] = 20

        #expect(!BudgetGuard(budgets: settings, entries: entries, now: Self.now, calendar: Self.calendar)
            .isAvoided("OpenAI"))
    }

    @Test func theMonthStartsAgainAtMidnightInTheMacsTimeZone() throws {
        let midnight = Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let entries = [Self.entry(9, at: midnight.addingTimeInterval(-1))]
        let settings = Self.budgets { $0.total = 10 }

        let march = BudgetGuard(budgets: settings, entries: entries, now: midnight.addingTimeInterval(-1),
                                calendar: Self.calendar)
        let april = BudgetGuard(budgets: settings, entries: entries, now: midnight, calendar: Self.calendar)

        #expect(try #require(march.status(of: .total)).spent.value == 9)
        #expect(try #require(april.status(of: .total)).spent.value == 0)
    }

    // Preflight of #164: Claude with `costBasis: unknown` counts, marked uncertain.
    @Test func anUncertainClaudeTurnCountsMarkedUncertain() throws {
        let entries = [Self.entry(2, provider: Budgets.claude, origin: .listEstimate, basis: .unknown)]
        let budgets = BudgetGuard(budgets: Self.budgets { $0.providers[Budgets.claude] = 10 }, entries: entries,
                                  now: Self.now, calendar: Self.calendar)

        let status = try #require(budgets.status(of: .provider(Budgets.claude)))
        #expect(status.spent.value == 2)
        #expect(status.spent.isUncertain)
    }

    // Acceptance of #164: a model without a price on a provider with a Budget is said, in the line and the screen.
    @Test func aTurnWithoutAPriceIsSaidNotCounted() throws {
        let unpriced = Self.entry(nil, origin: .unpriced)
        let budgets = BudgetGuard(budgets: Self.budgets { $0.providers["OpenAI"] = 10 }, entries: [unpriced],
                                  now: Self.now, calendar: Self.calendar)
        let unbudgeted = BudgetGuard(budgets: Budgets(), entries: [unpriced], now: Self.now, calendar: Self.calendar)

        let status = try #require(budgets.status(of: .provider("OpenAI")))
        #expect(status.unpricedTurns == 1)
        #expect(status.spent.value == 0)
        #expect(budgets.notice(after: unpriced.usage, of: "OpenAI") == .unpriced)
        #expect(unbudgeted.notice(after: unpriced.usage, of: "OpenAI") == nil)
        #expect(!String(localized: RouterLine.text(of: .unpriced)).isEmpty)
    }

    @Test func theLineWarnsPastTheThresholdOnly() {
        let settings = Self.budgets { $0.providers["OpenAI"] = 10 }
        let turn = Self.entry(8.5)
        let under = BudgetGuard(budgets: settings, entries: [Self.entry(1)], now: Self.now, calendar: Self.calendar)
        let past = BudgetGuard(budgets: settings, entries: [turn], now: Self.now, calendar: Self.calendar)
        let subscription = Self.entry(50, provider: Budgets.claude, mode: .subscription, origin: .listEstimate)

        #expect(under.notice(after: turn.usage, of: "OpenAI") == nil)
        #expect(past.notice(after: turn.usage, of: "OpenAI") == .reached(.provider("OpenAI"), share: 0.85))
        #expect(past.notice(after: subscription.usage, of: Budgets.claude) == nil)
    }
}
