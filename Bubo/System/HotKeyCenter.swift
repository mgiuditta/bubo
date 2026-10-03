import Foundation
import Observation

/// Owns the global shortcut that shows and hides the HUD, or held down dictates (push-to-talk), and remembers it; the
/// same shortcut plus ⇧, held down, only dictates into the prompt (spec 08); and the one that opens the Bolla, as «Chiedi
/// nel Panel» (#635).
@Observable
final class HotKeyCenter {
    /// The `UserDefaults` key of the saved shortcut.
    static let defaultsKey = "showHUDShortcut"
    /// The `UserDefaults` key of the saved shortcut of «Chiedi nel Panel».
    static let askDefaultsKey = "askInPanelShortcut"

    /// The shortcut currently in effect.
    private(set) var shortcut: KeyShortcut
    /// A message for the user when the last registration failed, otherwise `nil`.
    private(set) var problem: String?

    /// The shortcut of the sola dettatura; `nil` when the shortcut has ⇧ already, or when it could not be registered.
    private(set) var dictationShortcut: KeyShortcut?

    /// The shortcut that opens the Bolla with the keyboard in its field; it wins over the sola dettatura.
    private(set) var askShortcut: KeyShortcut

    @ObservationIgnored private let hotKey: GlobalHotKey
    @ObservationIgnored private let dictationHotKey: GlobalHotKey
    @ObservationIgnored private let askHotKey: GlobalHotKey
    @ObservationIgnored private let defaults: UserDefaults

    /// Creates the center and registers the saved shortcuts, or ⌥Spazio and ⌥⇧Spazio.
    ///
    /// - Parameters:
    ///   - press: Runs when the shortcut goes down, with `sending` false for the sola dettatura.
    ///   - release: Runs when either shortcut is let go.
    ///   - ask: Runs when the shortcut of «Chiedi nel Panel» goes down.
    init(defaults: UserDefaults = .standard, press: @escaping (_ sending: Bool) -> Void,
         release: @escaping () -> Void = {}, ask: @escaping () -> Void = {}) {
        self.defaults = defaults
        self.hotKey = GlobalHotKey(press: { press(true) }, release: release)
        self.dictationHotKey = GlobalHotKey(press: { press(false) }, release: release)
        self.askHotKey = GlobalHotKey(press: ask)
        self.shortcut = defaults.string(forKey: Self.defaultsKey).flatMap(KeyShortcut.init(rawValue:)) ?? .showHUD
        self.askShortcut = defaults.string(forKey: Self.askDefaultsKey).flatMap(KeyShortcut.init(rawValue:)) ?? .askInPanel
        apply(shortcut)
        let failure = problem
        applyAsk(askShortcut)
        problem = problem ?? failure
    }

    /// Switches to `newShortcut` and saves it, keeping the old one if registration fails.
    func change(to newShortcut: KeyShortcut) {
        guard newShortcut != askShortcut else {
            problem = String(localized: "\(newShortcut.displayName) apre già la bolla. Scegline un'altra.")
            return
        }
        let previous = shortcut
        if apply(newShortcut) {
            shortcut = newShortcut
            defaults.set(newShortcut.rawValue, forKey: Self.defaultsKey)
        } else {
            // Restoring the old shortcut must not hide why the new one failed.
            let failure = problem
            apply(previous)
            problem = failure
        }
    }

    /// Switches «Chiedi nel Panel» to `newShortcut` and saves it, keeping the old one if registration fails.
    func changeAsk(to newShortcut: KeyShortcut) {
        guard newShortcut != shortcut else {
            problem = String(localized: "\(newShortcut.displayName) mostra già l'HUD. Scegline un'altra.")
            return
        }
        let previous = askShortcut
        askShortcut = newShortcut
        if applyAsk(newShortcut) {
            defaults.set(newShortcut.rawValue, forKey: Self.askDefaultsKey)
            // The old shortcut may have kept the sola dettatura off.
            applyDictation(of: shortcut)
        } else {
            let failure = problem
            askShortcut = previous
            applyAsk(previous)
            problem = failure
        }
    }

    @discardableResult
    private func applyAsk(_ candidate: KeyShortcut) -> Bool {
        askHotKey.unregister()
        // The candidate may be the current sola dettatura, which Bubo itself holds: the Bolla takes it.
        if candidate == dictationShortcut {
            dictationHotKey.unregister()
            dictationShortcut = nil
        }
        do {
            try askHotKey.register(candidate)
            problem = nil
            return true
        } catch .alreadyInUse {
            problem = String(localized: "\(candidate.displayName) è già usata da un'altra app. Scegline un'altra.")
        } catch {
            problem = String(localized: "Non riesco a registrare \(candidate.displayName).")
        }
        return false
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
        guard let variant = shortcut.dictationVariant, variant != askShortcut else { return }
        do {
            try dictationHotKey.register(variant)
            dictationShortcut = variant
        } catch {
            problem = String(localized: "Non riesco a registrare \(variant.displayName) per la sola dettatura.")
        }
    }
}
