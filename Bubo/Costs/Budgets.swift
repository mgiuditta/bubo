import Foundation

/// The user's monthly Budgets (spec 18): per provider paid per use, per Progetto and in total; all off by default.
///
/// Only Spesa counts: the subscription has the Quota, and the models on the Mac, Apple FM and Jev cost nothing.
nonisolated struct Budgets: Codable, Equatable, Sendable {
    /// The monthly limits in US dollars, by provider as the CostLedger names it: "Anthropic" for Claude with the API
    /// key, an endpoint's name for the others.
    var providers: [String: Decimal] = [:]
    /// The monthly limits in US dollars, by the path of the Progetto's folder.
    var projects: [String: Decimal] = [:]
    /// The monthly limit on all the Spesa; `nil` without one.
    var total: Decimal?
    /// The share of a Budget, from 0 to 1, past which Bubo warns and the router avoids it.
    var threshold = 0.8

    /// The name the CostLedger gives Claude, whose Budget counts only the turns paid with the API key.
    static let claude = "Anthropic"
    /// The name the CostLedger gives GitHub Copilot, whose turns are all Spesa, estimated from their tokens.
    static let copilot = "GitHub Copilot"

    /// The limit of `scope`; `nil` when it has no Budget.
    func limit(of scope: BudgetGuard.Scope) -> Decimal? {
        switch scope {
        case let .provider(name): providers[name]
        case let .project(folder): projects[folder.path(percentEncoded: false)]
        case .total: total
        }
    }

    /// Sets the limit of `scope` to `limit`; `nil` turns its Budget off.
    mutating func setLimit(_ limit: Decimal?, of scope: BudgetGuard.Scope) {
        switch scope {
        case let .provider(name): providers[name] = limit
        case let .project(folder): projects[folder.path(percentEncoded: false)] = limit
        case .total: total = limit
        }
    }
}
