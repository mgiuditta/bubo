import Foundation

extension SessionStore {
    /// The defaults key of the Progetto chosen for each Linear team, as `[team: path]`.
    static let linearTeamProjectsKey = "linearTeamProjects"

    /// The Progetti Bubo knows: those of the Sessioni, then those with only Bozze.
    var knownProjects: [URL] {
        var seen = Set(projects.map(\.standardizedFileURL.path))
        return projects + drafts.drafts.map(\.project).filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// The Progetto of the Linear issue of `link`: the one whose folder Linear names, else the one chosen before for
    /// its team in `defaults`; `nil` when Bubo has to ask.
    func project(for link: LinearLink, defaults: UserDefaults = .standard) -> URL? {
        let remembered = defaults.dictionary(forKey: Self.linearTeamProjectsKey) as? [String: String] ?? [:]
        return link.project(among: knownProjects, remembered: remembered)
    }

    /// Remembers `project` for the team of `link` in `defaults`, so its next issues go there without asking.
    func remember(_ project: URL, forTeamOf link: LinearLink, defaults: UserDefaults = .standard) {
        var remembered = defaults.dictionary(forKey: Self.linearTeamProjectsKey) as? [String: String] ?? [:]
        remembered[link.team] = project.standardizedFileURL.path
        defaults.set(remembered, forKey: Self.linearTeamProjectsKey)
    }

    /// A Linear issue run from Linear's custom script: a Bozza on `project`, never a Sessione, with what Linear sent
    /// as its text and the branch from Linear's. The same issue again leads to its Bozza or Sessione.
    ///
    /// - Returns: Whether a Bozza was added.
    @discardableResult
    func receive(_ link: LinearLink, in project: URL) -> Bool {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isFolder), isFolder.boolValue
        else { return false }
        return addDraft(Draft(title: link.title, text: link.prompt, project: project, issue: link.issue,
                              branch: link.branch))
    }
}
