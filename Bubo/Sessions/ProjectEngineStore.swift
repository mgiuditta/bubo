import Foundation

/// The engine and model each Progetto's new Sessioni start on, as the user set them with «Usa sempre per questo
/// Progetto» (ADR 0012). Kept in Bubo's defaults; a Progetto without one starts on Claude.
@Observable
final class ProjectEngineStore {
    /// The defaults key: the JSON of the choices, by Progetto path.
    static let key = "sessions.projectEngines"

    @ObservationIgnored private let defaults: UserDefaults
    private var choices: [String: EngineChoice]

    /// Creates a store kept in `defaults`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choices = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: EngineChoice].self, from: $0) } ?? [:]
    }

    /// The choice the new Sessioni of `project` start on: Claude unless the user set another.
    func choice(for project: URL) -> EngineChoice {
        choices[project.standardizedFileURL.path] ?? .claude
    }

    /// Makes the new Sessioni of `project` start on `choice`.
    func setChoice(_ choice: EngineChoice, for project: URL) {
        choices[project.standardizedFileURL.path] = choice == .claude ? nil : choice
        defaults.set(try? JSONEncoder().encode(choices), forKey: Self.key)
    }
}
