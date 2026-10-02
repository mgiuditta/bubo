import Foundation

/// One installation of a plugin, as `installed_plugins.json` or `claude plugin list --json` records it.
nonisolated struct PluginInstallation: Sendable, Equatable {
    let scope: PluginScope
    /// The Progetto of a `project` or `local` installation.
    let projectPath: URL?
    /// The folder the plugin loads from.
    let installPath: URL?
    let version: String?
    let gitCommitSha: String?
    /// Whether the merged settings turn the plugin on.
    var isEnabled: Bool
}

nonisolated extension PluginInstallation {
    /// Whether the installation counts with `project` chosen: every `user` and `managed` one, and the `project`
    /// and `local` ones of `project`.
    func counts(in project: URL?) -> Bool {
        switch scope {
        case .user, .managed: true
        case .project, .local: projectPath.map { Self.isSameFolder($0, project) } ?? false
        }
    }

    /// Whether `folder` and `other` are the same folder, symbolic links such as `/tmp` and `/private/tmp`, trailing
    /// slash and `.` and `..` aside.
    static func isSameFolder(_ folder: URL, _ other: URL?) -> Bool {
        guard let other else { return false }
        return TrustGate.realPath(folder.path) == TrustGate.realPath(other.path)
    }
}
