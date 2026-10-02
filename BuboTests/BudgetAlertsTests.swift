import Foundation
import Testing
@testable import Bubo

/// #164: the notification of a Budget past its threshold.
@MainActor
struct BudgetAlertsTests {
    let defaults = UserDefaults(suiteName: "BudgetAlertsTests-\(UUID().uuidString)")!
    let ledger = CostLedger()
    let settings: BudgetSettings
    let alerts: BudgetAlerts

    init() {
        settings = BudgetSettings(defaults: defaults)
        settings.budgets.providers["OpenAI"] = 10
        alerts = BudgetAlerts(ledger: ledger, settings: settings, defaults: defaults) { _ in }
    }

    func record(_ cost: Decimal, at date: Date = .now) {
        ledger.record(TurnUsage(mode: .apiKey, cost: cost, basis: .list, isComplete: true, models: [],
                                origin: .priceTable),
                      turn: UUID().uuidString, question: UUID(), provider: "OpenAI", at: date)
    }

    // Acceptance of #164: the warning comes with the turn that passes the threshold, not later.
    @Test func theTurnPastTheThresholdPostsAtOnce() throws {
        record(5)
        #expect(alerts.check(after: try #require(ledger.entries.last)).isEmpty)

        record(4)
        let posted = alerts.check(after: try #require(ledger.entries.last))

        #expect(posted.map(\.scope) == [.provider("OpenAI")])
        #expect(posted.map(\.level) == [.threshold])
    }

    @Test func eachLevelPostsOnceAMonth() throws {
        record(9)
        #expect(alerts.check(after: try #require(ledger.entries.last)).count == 1)
        record(0.1)
        #expect(alerts.check(after: try #require(ledger.entries.last)).isEmpty)

        record(1)
        #expect(alerts.check(after: try #require(ledger.entries.last)).map(\.level) == [.exhausted])
    }

    @Test func aRaisedBudgetWarnsAgainWhenReached() throws {
        record(9)
        alerts.check(after: try #require(ledger.entries.last))

        settings.budgets.providers["OpenAI"] = 20
        record(8)

        #expect(alerts.check(after: try #require(ledger.entries.last)).map(\.limit) == [20])
    }

    @Test func theSettingsAreKept() {
        settings.budgets.threshold = 0.9

        #expect(BudgetSettings(defaults: defaults).budgets == settings.budgets)
    }
}
