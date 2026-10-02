import Foundation
import Observation

/// Owns the global shortcut that shows and hides the HUD, or held down dictates (push-to-talk), and remembers it; the
/// same shortcut plus ⇧, held down, only dictates into the prompt (spec 08).
@Observable
final class HotKeyCenter {
    /// The `UserDefaults` key of the saved shortcut.
    static let defaultsKey = "showHUDShortcut"

    /// The shortcut currently in effect.
    private(set) var shortcut: KeyShortcut
    /// A message for the user when the last registration failed, otherwise `nil`.
    private(set) var problem: String?

    /// The shortcut of the sola dettatura; `nil` when the shortcut has ⇧ already, or when it could not be registered.
    private(set) var dictationShortcut: KeyShortcut?

    @ObservationIgnored private let hotKey: GlobalHotKey
    @ObservationIgnored private let dictationHotKey: GlobalHotKey
    @ObservationIgnored private let defaults: UserDefaults

    /// Creates the center and registers the saved shortcut, or ⌥Spazio.
    ///
    /// - Parameters:
    ///   - press: Runs when the shortcut goes down, with `sending` false for the sola dettatura.
    ///   - release: Runs when either shortcut is let go.
    init(defaults: UserDefaults = .standard, press: @escaping (_ sending: Bool) -> Void,
         release: @escaping () -> Void = {}) {
        self.defaults = defaults
        self.hotKey = GlobalHotKey(press: { press(true) }, release: release)
        self.dictationHotKey = GlobalHotKey(press: { press(false) }, release: release)
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
        // The candidate may be the current dictation variant, which Bubo itself holds.
        dictationHotKey.unregister()
        dictationShortcut = nil
        do {
            try hotKey.register(candidate)
            problem = nil
            applyDictation(of: candidate)
            return true
        } catch .alreadyInUse {
            problem = String(localized: "\(candidate.displayName) è già usata da un'altra app. Scegline un'altra.")
        } catch {
            problem = String(localized: "Non riesco a registrare \(candidate.displayName).")
        }
        return false
    }

    /// Registers `shortcut` plus ⇧ for the sola dettatura, or turns the sola dettatura off.
    private func applyDictation(of shortcut: KeyShortcut) {
        dictationHotKey.unregister()
        dictationShortcut = nil
        guard let variant = shortcut.dictationVariant else { return }
        do {
            try dictationHotKey.register(variant)
            dictationShortcut = variant
        } catch {
            problem = String(localized: "Non riesco a registrare \(variant.displayName) per la sola dettatura.")
        }
    }
}
