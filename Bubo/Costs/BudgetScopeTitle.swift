import Foundation

extension BudgetGuard.Scope {
    /// What the scope is called: Claude, a provider (a brand, never translated), a Progetto's folder, or the total.
    var name: String {
        switch self {
        case let .provider(name) where name == Budgets.claude:
            String(localized: "Claude con API key", comment: "The Budget of Claude paid with the user's API key.")
        case let .provider(name): name
        case let .project(folder): folder.lastPathComponent
        case .total: String(localized: "Totale", comment: "The Budget on all the Spesa, in the Budget settings.")
        }
    }

    /// The Budget as a notification and the reason line name it, such as «Budget di OpenAI» or «Budget totale».
    var budgetTitle: String {
        switch self {
        case .total:
            String(localized: "Budget totale", comment: "The Budget on all the Spesa.")
        case let .provider(name) where name == Budgets.claude:
            String(localized: "Budget di Claude", comment: "The Budget of Claude paid with the user's API key.")
        case .provider, .project:
            String(localized: "Budget di \(name)",
                   comment: "The Budget of a provider (a brand) or of a Progetto (its folder), such as «Budget di OpenAI».")
        }
    }
}
