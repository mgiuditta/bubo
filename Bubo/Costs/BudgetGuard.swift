import Foundation

/// What is left of each Budget this month, from the CostLedger's turns (spec 18, Moduli): read again at every turn and
/// every change of a Budget, so the residue is always the current one.
///
/// The month is the calendar month in the Mac's time zone: at midnight of the first day every residue starts again,
/// and a turn across midnight counts in the month it ends. Only Spesa counts; the Cronologia CLI is not in the ledger.
struct BudgetGuard {
    /// What a Budget limits.
    nonisolated enum Scope: Codable, Hashable, Sendable {
        /// One provider paid per use, as the CostLedger names it.
        case provider(String)
        /// The Spesa of a Progetto's Sessioni.
        case project(URL)
        /// All the Spesa.
        case total
    }

    /// How far a Budget is.
    nonisolated enum Level: Int, Comparable, Sendable {
        /// Under the threshold.
        case below
        /// At the threshold or past it: Bubo warns, and the router avoids the provider when it has an alternative.
        case threshold
        /// Spent in full.
        case exhausted

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One Budget this month.
    struct Status: Equatable {
        let scope: Scope
        /// The monthly limit, in US dollars.
        let limit: Decimal
        /// The Spesa of the month; uncertain when a Claude turn was priced at a guessed rate (`costBasis: unknown`).
        let spent: CostLedger.Amount
        /// The turns of the month with no price, which the Budget cannot count.
        let unpricedTurns: Int
        let level: Level

        /// The share spent, from 0 up; a limit of zero is spent at once.
        var share: Double {
            guard limit > 0 else { return 1 }
            return NSDecimalNumber(decimal: spent.value / limit).doubleValue
        }

        /// What is left, never below zero.
        var remaining: Decimal {
            max(limit - spent.value, 0)
        }
    }

    /// Reads `budgets` against `entries` in the month of `now`.
    init(budgets: Budgets, entries: [CostLedger.Entry], now: Date = .now, calendar: Calendar = .current) {
        self.budgets = budgets
        let month = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, end: now)
        // The interval's end is the next month's start: a turn at that instant counts there.
        self.entries = entries.filter { $0.date >= month.start && $0.date < month.end && $0.usage.mode == .apiKey }
    }

    private let budgets: Budgets
    /// The turns of the month on a key: the paid ones, those without a price and the free ones, filtered further.
    private let entries: [CostLedger.Entry]

    /// The Budget of `scope` this month; `nil` when it has none.
    func status(of scope: Scope) -> Status? {
        guard let limit = budgets.limit(of: scope) else { return nil }
        var spent = CostLedger.Amount()
        var unpriced = 0
        for entry in entries where Self.counts(entry, in: scope) {
            if entry.usage.origin == .unpriced {
                unpriced += 1
            } else if entry.usage.unit == .spesa {
                spent.add(entry.usage)
            }
        }
        let below = Status(scope: scope, limit: limit, spent: spent, unpricedTurns: unpriced, level: .below)
        let level: Level = below.share >= 1 ? .exhausted : below.share >= budgets.threshold ? .threshold : .below
        return Status(scope: scope, limit: limit, spent: spent, unpricedTurns: unpriced, level: level)
    }

    /// The Budgets a turn of `provider` on `project` counts in: its provider's, its Progetto's, the total.
    func statuses(provider: String, project: URL?) -> [Status] {
        var scopes: [Scope] = [.provider(provider), .total]
        if let project { scopes.append(.project(project)) }
        return scopes.compactMap(status(of:))
    }

    /// The tightest of the Budgets a turn of `provider` on `project` counts in, the one spent the most; `nil` without
    /// any.
    func tightest(provider: String, project: URL? = nil) -> Status? {
        statuses(provider: provider, project: project).max { $0.share < $1.share }
    }

    /// What a turn of `provider` on `project` may still spend (spec 18, Soglia e 100%).
    nonisolated enum Allowance: Equatable, Sendable {
        /// No Budget counts the turn.
        case unlimited
        /// Up to this many US dollars, the least that is left among the Budgets the turn counts in: Claude's
        /// `maxBudgetUsd`.
        case upTo(Decimal)
        /// A Budget the turn counts in is spent in full: nothing is sent without the user's choice.
        case exhausted(Scope)
    }

    /// What a turn of `provider` on `project` may still spend, before it is sent: the shared residue, read again at
    /// every turn of every Sessione and Domanda, never split ahead between them.
    func allowance(provider: String, project: URL? = nil) -> Allowance {
        let statuses = statuses(provider: provider, project: project)
        if let spent = statuses.first(where: { $0.level == .exhausted }) { return .exhausted(spent.scope) }
        guard let least = statuses.map(\.remaining).min() else { return .unlimited }
        return .upTo(least)
    }

    /// Whether the router avoids `provider` in its automatic choices: a Budget it counts in is at the threshold.
    func isAvoided(_ provider: String) -> Bool {
        (tightest(provider: provider)?.level ?? .below) >= .threshold
    }

    /// What the reason line says of the Budgets after `usage`, a turn of `provider` on `project`; `nil` when there is
    /// nothing to say.
    func notice(after usage: TurnUsage, of provider: String, on project: URL? = nil) -> BudgetNotice? {
        guard usage.mode == .apiKey, usage.origin != .free else { return nil }
        let statuses = statuses(provider: provider, project: project)
        guard let tightest = statuses.max(by: { $0.share < $1.share }) else { return nil }
        if usage.origin == .unpriced { return .unpriced }
        guard tightest.level >= .threshold else { return nil }
        return .reached(tightest.scope, share: tightest.share)
    }

    /// Whether `entry` counts in the Budget of `scope`.
    private static func counts(_ entry: CostLedger.Entry, in scope: Scope) -> Bool {
        switch scope {
        case let .provider(name): (entry.provider ?? Budgets.claude) == name
        case let .project(folder): entry.project?.standardizedFileURL == folder.standardizedFileURL
        case .total: true
        }
    }
}

/// What the reason line under an answer says of the Budgets, after the turn.
nonisolated enum BudgetNotice: Equatable, Sendable {
    /// The tightest Budget the turn counts in is past the threshold, at `share`.
    case reached(BudgetGuard.Scope, share: Double)
    /// The model has no price, on a provider with a Budget: the turn counts only its tokens, outside the Budget.
    case unpriced
}
