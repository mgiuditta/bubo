import AppKit

/// Shows or hides Bubo's Dock icon; the menu bar item stays either way.
enum DockIcon {
    /// The `UserDefaults` key of the preference.
    static let defaultsKey = "showsDockIcon"

    /// Applies the preference to the running app.
    static func apply(isVisible: Bool) {
        NSApp.setActivationPolicy(isVisible ? .regular : .accessory)
    }
}
