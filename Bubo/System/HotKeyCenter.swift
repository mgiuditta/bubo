import Foundation
import Observation

/// Owns the global shortcut that shows and hides the HUD, and remembers it.
@Observable
final class HotKeyCenter {
    /// The `UserDefaults` key of the saved shortcut.
    static let defaultsKey = "showHUDShortcut"

    /// The shortcut currently in effect.
    private(set) var shortcut: KeyShortcut
    /// A message for the user when the last registration failed, otherwise `nil`.
    private(set) var problem: String?

    @ObservationIgnored private let hotKey: GlobalHotKey
    @ObservationIgnored private let defaults: UserDefaults

    /// Creates the center and registers the saved shortcut, or ⌥Spazio.
    init(defaults: UserDefaults = .standard, action: @escaping () -> Void) {
        self.defaults = defaults
        self.hotKey = GlobalHotKey(action: action)
        self.shortcut = defaults.string(forKey: Self.defaultsKey).flatMap(KeyShortcut.init(rawValue:)) ?? .showHUD
        apply(shortcut)
    }

    /// Switches to `newShortcut` and saves it, keeping the old one if registration fails.
    func change(to newShortcut: KeyShortcut) {
        let previous = shortcut
        if apply(newShortcut) {
            shortcut = newShortcut
            defaults.set(newShortcut.rawValue, forKey: Self.defaultsKey)
        } else {
            apply(previous)
        }
    }

    @discardableResult
    private func apply(_ candidate: KeyShortcut) -> Bool {
        do {
            try hotKey.register(candidate)
            problem = nil
            return true
        } catch .alreadyInUse {
            problem = String(localized: "\(candidate.displayName) è già usata da un'altra app. Scegline un'altra.")
        } catch {
            problem = String(localized: "Non riesco a registrare \(candidate.displayName).")
        }
        return false
    }
}
