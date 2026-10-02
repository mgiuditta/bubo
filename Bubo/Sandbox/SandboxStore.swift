import Foundation

/// The Sandbox Progetto by Progetto (spec 22): whether it is on, off unless the user turns it on, and the hosts and
/// folders the user let it reach beyond the preset.
///
/// Kept in Bubo's defaults, never in the Progetto's `.claude/settings*.json`. A change counts from the next turn of
/// each Sessione, since every turn starts its own `claude`.
@Observable
final class SandboxStore {
    /// The defaults key: the paths of the Progetti with the Sandbox on.
    static let key = "sandbox.projects"
    /// The defaults key: the allowed hosts, by Progetto path.
    static let domainsKey = "sandbox.domains"
    /// The defaults key: the allowed folders, by Progetto path.
    static let foldersKey = "sandbox.folders"

    @ObservationIgnored private let defaults: UserDefaults
    private var enabled: Set<String>
    private var domains: [String: [String]]
    private var folders: [String: [String]]

    /// Creates a store kept in `defaults`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = Set(defaults.stringArray(forKey: Self.key) ?? [])
        domains = defaults.dictionary(forKey: Self.domainsKey) as? [String: [String]] ?? [:]
        folders = defaults.dictionary(forKey: Self.foldersKey) as? [String: [String]] ?? [:]
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

    /// The hosts and folders the Sandbox of `project` also reaches.
    func allowances(in project: URL) -> SandboxAllowances {
        let path = Self.path(of: project)
        return SandboxAllowances(domains: domains[path] ?? [], folders: folders[path] ?? [])
    }

    /// Lets the Sandbox of `project` reach `allowance` from the next turn; nothing if it already does.
    func allow(_ allowance: SandboxAllowance, in project: URL) {
        let path = Self.path(of: project)
        switch allowance {
        case let .domain(host):
            guard domains[path]?.contains(host) != true else { return }
            domains[path, default: []].append(host)
            defaults.set(domains, forKey: Self.domainsKey)
        case let .folder(folder):
            guard folders[path]?.contains(folder) != true else { return }
            folders[path, default: []].append(folder)
            defaults.set(folders, forKey: Self.foldersKey)
        }
    }

    /// Stops the Sandbox of `project` reaching `allowance`, from the next turn.
    func remove(_ allowance: SandboxAllowance, in project: URL) {
        let path = Self.path(of: project)
        switch allowance {
        case let .domain(host):
            domains[path]?.removeAll { $0 == host }
            if domains[path]?.isEmpty == true { domains[path] = nil }
            defaults.set(domains, forKey: Self.domainsKey)
        case let .folder(folder):
            folders[path]?.removeAll { $0 == folder }
            if folders[path]?.isEmpty == true { folders[path] = nil }
            defaults.set(folders, forKey: Self.foldersKey)
        }
    }

    private static func path(of project: URL) -> String {
        let path = project.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
