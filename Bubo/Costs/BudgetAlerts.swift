import Foundation

/// Posts a notification when a turn takes a Budget past its threshold, and again when it spends it (spec 18): once per
/// Budget, level and limit each month, so a raised Budget warns again when it is reached again.
final class BudgetAlerts {
    /// Creates alerts that read `ledger` against `settings` and post each Budget reached with `post`.
    init(ledger: CostLedger, settings: BudgetSettings = .shared, defaults: UserDefaults = .standard,
         calendar: Calendar = .current, post: @escaping (BudgetGuard.Status) async -> Void) {
        self.ledger = ledger
        self.settings = settings
        self.defaults = defaults
        self.calendar = calendar
        self.post = post
    }

    private let ledger: CostLedger
    private let settings: BudgetSettings
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let post: (BudgetGuard.Status) async -> Void

    /// Reads the Budgets `entry` counts in, as soon as the ledger has it, and posts those just reached.
    ///
    /// - Returns: The Budgets posted.
    @discardableResult
    func check(after entry: CostLedger.Entry, now: Date = .now) -> [BudgetGuard.Status] {
        guard entry.usage.unit == .spesa else { return [] }
        let budgets = BudgetGuard(budgets: settings.budgets, entries: ledger.entries, now: now, calendar: calendar)
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var posted = Set(defaults.stringArray(forKey: Self.key) ?? [])
        let reached = budgets.statuses(provider: entry.provider ?? Budgets.claude, project: entry.project)
            .filter { $0.level >= .threshold }
            .filter { posted.insert(Self.key(of: $0, in: month)).inserted }
        guard !reached.isEmpty else { return [] }
        // Only this month's keys matter: the older ones go.
        let prefix = Self.monthKey(month)
        defaults.set(posted.filter { $0.hasPrefix(prefix) }.sorted(), forKey: Self.key)
        for status in reached {
            Task { await post(status) }
        }
        return reached
    }

    private static func key(of status: BudgetGuard.Status, in month: Date) -> String {
        let scope = switch status.scope {
        case let .provider(name): "provider:\(name)"
        case let .project(folder): "project:\(folder.path(percentEncoded: false))"
        case .total: "total"
        }
        return "\(monthKey(month))|\(scope)|\(status.level.rawValue)|\(status.limit)"
    }

    private static func monthKey(_ month: Date) -> String {
        "\(Int(month.timeIntervalSinceReferenceDate))"
    }

    private static let key = "costs.budgetAlertsPosted"
}
