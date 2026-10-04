import Foundation
import os

/// The Budgets the user set in Impostazioni › Budget, kept in the user defaults; every change counts at once.
@Observable
final class BudgetSettings {
    /// The one shared by the settings window, the router and the reason line.
    static let shared = BudgetSettings()

    /// The limits and the threshold.
    var budgets: Budgets {
        didSet { persist() }
    }

    /// Creates the settings saved in `defaults`; with none saved, every Budget is off.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else {
            budgets = Budgets()
            return
        }
        do {
            budgets = try JSONDecoder().decode(Budgets.self, from: data)
        } catch {
            Logger.costs.error("Budget unreadable, all off: \(String(describing: error), privacy: .public)")
            budgets = Budgets()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(budgets), forKey: Self.key)
        } catch {
            Logger.costs.error("Budget not saved: \(String(describing: error), privacy: .public)")
        }
    }

    private static let key = "costs.budgets"
}
