/// A tab of the settings window, kept in `UserDefaults` so that a button elsewhere can open one.
enum SettingsTab: String {
    case general, appearance, account, permissions, models, budget, machines, voice, iphone, deliveries, shortcuts,
         diagnostics

    /// `UserDefaults` key of the tab shown.
    static let defaultsKey = "settings.tab"
}
