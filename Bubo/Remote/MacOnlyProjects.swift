import Foundation

/// The Progetti solo Mac (spec 21): their Sessioni never leave the Mac, so the iPhone does not see them.
///
/// Kept in Bubo's defaults by Progetto path; a change counts at the next publication of the Telecomando.
@Observable
final class MacOnlyProjects {
    /// The defaults key: the paths of the Progetti solo Mac.
    static let key = "remote.macOnlyProjects"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var paths: Set<String>

    /// Creates the list kept in `defaults`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        paths = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    /// Whether the Sessioni of `project` stay on the Mac.
    func isMacOnly(_ project: URL) -> Bool {
        paths.contains(Self.path(of: project))
    }

    /// Keeps the Sessioni of `project` on the Mac, or lets them out again.
    func setMacOnly(_ isMacOnly: Bool, for project: URL) {
        let path = Self.path(of: project)
        if isMacOnly { paths.insert(path) } else { paths.remove(path) }
        defaults.set(paths.sorted(), forKey: Self.key)
    }

    private static func path(of project: URL) -> String {
        let path = project.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
