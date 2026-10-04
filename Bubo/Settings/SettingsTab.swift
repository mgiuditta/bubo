import Foundation

/// A tab of the settings window.
enum SettingsTab: String {
    case general, appearance, account, permissions, models, budget, machines, voice, iPhone, deliveries, shortcuts,
         updates, diagnostics

    /// The defaults key of the tab shown.
    static let defaultsKey = "settings.tab"

    /// Makes `self` the tab the settings window shows, open or at its next opening.
    func select(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
