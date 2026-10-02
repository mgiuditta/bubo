import Foundation

/// Where a plugin is installed and turned on, with the same words everywhere (spec 20).
nonisolated enum PluginScope: String, Sendable, CaseIterable {
    case user, project, local, managed

    /// "Per me", "Per questo Progetto", "Solo io in questo Progetto", "Gestito dall'organizzazione".
    var title: LocalizedStringResource {
        switch self {
        case .user: "Per me"
        case .project: "Per questo Progetto"
        case .local: "Solo io in questo Progetto"
        case .managed: "Gestito dall'organizzazione"
        }
    }
}
