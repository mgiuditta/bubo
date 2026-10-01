import Foundation

/// Whether the Sandbox is on, Progetto by Progetto (spec 22): off unless the user turns it on.
///
/// Kept in Bubo's defaults, never in the Progetto's `.claude/settings*.json`. A change counts from the next turn of
/// each Sessione, since every turn starts its own `claude`.
@Observable
final class SandboxStore {
    /// The defaults key: the paths of the Progetti with the Sandbox on.
    static let key = "sandbox.projects"

    @ObservationIgnored private let defaults: UserDefaults
    private var enabled: Set<String>

    /// Creates a store kept in `defaults`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    /// Whether the Sandbox is on in `project`.
    func isEnabled(in project: URL) -> Bool {
        enabled.contains(Self.path(of: project))
    }

    /// Turns the Sandbox on or off in `project`.
    func setEnabled(_ isEnabled: Bool, in project: URL) {
        let path = Self.path(of: project)
        if isEnabled { enabled.insert(path) } else { enabled.remove(path) }
        defaults.set(enabled.sorted(), forKey: Self.key)
    }

    private static func path(of project: URL) -> String {
        let path = project.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
