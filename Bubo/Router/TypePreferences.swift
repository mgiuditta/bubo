import Foundation
import os

/// The preferences for each Tipo di richiesta the user set with "Usa sempre per «Tipo»", for all the Domande;
/// revocable in Impostazioni › Modelli.
///
/// Kept in the user defaults. A cloud endpoint is saved only after its consent, and answers only while it has it:
/// the router checks again at every Domanda.
@Observable
final class TypePreferences {
    /// The one shared by the HUD and the settings window.
    static let shared = TypePreferences()

    /// Who answers each Tipo with a preference.
    private(set) var choices: [RequestType: TypePreference]

    /// Creates the preferences saved in `defaults`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choices = [:]
        guard let data = defaults.data(forKey: Self.key) else { return }
        do {
            let saved = try JSONDecoder().decode([String: TypePreference].self, from: data)
            for (type, choice) in saved {
                if let type = RequestType(rawValue: type) { choices[type] = choice }
            }
        } catch {
            Logger(subsystem: "com.mgiuditta.bubo", category: "router")
                .error("Type preferences unreadable, back to the defaults: \(String(describing: error), privacy: .public)")
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Makes `choice` answer the Domande of `type` from now on.
    func set(_ choice: TypePreference, for type: RequestType) {
        choices[type] = choice
        persist()
    }

    /// Gives `type` back its default.
    func remove(for type: RequestType) {
        choices[type] = nil
        persist()
    }

    private func persist() {
        let saved = Dictionary(uniqueKeysWithValues: choices.map { ($0.key.rawValue, $0.value) })
        do {
            defaults.set(try JSONEncoder().encode(saved), forKey: Self.key)
        } catch {
            Logger(subsystem: "com.mgiuditta.bubo", category: "router")
                .error("Type preferences not saved: \(String(describing: error), privacy: .public)")
        }
    }

    private static let key = "router.typePreferences"
}
