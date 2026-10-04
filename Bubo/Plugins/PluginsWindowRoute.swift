import Foundation

/// Where the Plugin window goes when another part of Bubo opens it, such as the panel of the configuration (04)
/// from its plugin errors: the Progetto, on Da sistemare.
@MainActor @Observable final class PluginsWindowRoute {
    /// The one route of the app's one Plugin window.
    static let shared = PluginsWindowRoute()

    /// The Progetto whose problems to show; `nil` once the window has taken it.
    private(set) var problemsProject: URL?

    /// Asks the window to show Da sistemare for `project`.
    func showProblems(of project: URL) {
        problemsProject = project
    }

    /// The Progetto asked for, which the window takes once.
    func takeProblemsProject() -> URL? {
        defer { problemsProject = nil }
        return problemsProject
    }
}
